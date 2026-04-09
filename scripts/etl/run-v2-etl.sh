#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${ROOT_DIR}/docs/logs"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# Optional run correlation token used to prefix the runner log filename.
RAW_CORRELATION_ID="${CORRELATION_ID:-}"
CORRELATION_ID=""
if [[ -n "${RAW_CORRELATION_ID}" ]]; then
  CORRELATION_ID="$(printf '%s' "${RAW_CORRELATION_ID}" | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z0-9')"
  if [[ -z "${CORRELATION_ID}" ]]; then
    echo "ERROR: CORRELATION_ID provided but empty after normalization"
    exit 1
  fi
fi
LOG_PREFIX=""
if [[ -n "${CORRELATION_ID}" ]]; then
  LOG_PREFIX="${CORRELATION_ID}_"
fi
LOG_FILE="${LOG_DIR}/${LOG_PREFIX}v2_etl_${TIMESTAMP}.log"

# Runtime inputs and toggles (can be overridden via environment variables).
ACCIDENTS_CSV="${ACCIDENTS_CSV:-${ROOT_DIR}/raw/archive/US_Accidents_March23.csv}"
AIR_DIR="${AIR_DIR:-${ROOT_DIR}/raw}"
AIR_START_YEAR="${AIR_START_YEAR:-2016}"
AIR_END_YEAR="${AIR_END_YEAR:-2023}"
RULES_JSON="${RULES_JSON:-${ROOT_DIR}/scripts/analysis/rules.json}"
PROGRESS_EVERY_ACCIDENTS="${PROGRESS_EVERY_ACCIDENTS:-250000}"
PROGRESS_EVERY_AIR="${PROGRESS_EVERY_AIR:-5000}"
TOP_ISSUES="${TOP_ISSUES:-10}"
RUN_FACT_ACCIDENT_V2="${RUN_FACT_ACCIDENT_V2:-1}"
RUN_FACT_AIR_V2="${RUN_FACT_AIR_V2:-1}"
ROW_LIMIT_ACCIDENTS="${ROW_LIMIT_ACCIDENTS:-0}"
ROW_LIMIT_AIR="${ROW_LIMIT_AIR:-0}"
MISSING_FILE_MODE="${MISSING_FILE_MODE:-warn}"

# Ensure log directory exists, then mirror all stdout/stderr to file + terminal.
mkdir -p "${LOG_DIR}"
exec > >(tee -a "${LOG_FILE}") 2>&1

RUN_START_EPOCH="$(date +%s)"
RUN_START_HUMAN="$(date -Iseconds)"

if [[ "${AIR_START_YEAR}" -gt "${AIR_END_YEAR}" ]]; then
  echo "ERROR: AIR_START_YEAR must be <= AIR_END_YEAR"
  echo "  AIR_START_YEAR=${AIR_START_YEAR}"
  echo "  AIR_END_YEAR=${AIR_END_YEAR}"
  exit 1
fi

# Shared helper for timed, clearly delimited ETL phases.
run_step() {
  local label="$1"
  shift
  local step_start step_end
  step_start="$(date +%s)"
  echo
  echo "=== ${label} ==="
  echo "started_at: $(date -Iseconds)"
  "$@"
  step_end="$(date +%s)"
  echo "finished_at: $(date -Iseconds)"
  echo "step_runtime_seconds: $((step_end - step_start))"
}

echo "V2 ETL runner"
echo "started_at: ${RUN_START_HUMAN}"
echo "log_file: ${LOG_FILE}"
echo "correlation_id: ${CORRELATION_ID:-<none>}"
echo "accidents_csv: ${ACCIDENTS_CSV}"
echo "air_dir: ${AIR_DIR}"
echo "air_year_range: ${AIR_START_YEAR}-${AIR_END_YEAR}"
echo "rules_json: ${RULES_JSON}"
echo "progress_every_accidents: ${PROGRESS_EVERY_ACCIDENTS}"
echo "progress_every_air: ${PROGRESS_EVERY_AIR}"
echo "top_issues: ${TOP_ISSUES}"
echo "run_fact_accident_v2: ${RUN_FACT_ACCIDENT_V2}"
echo "run_fact_air_v2: ${RUN_FACT_AIR_V2}"
echo "row_limit_accidents: ${ROW_LIMIT_ACCIDENTS}"
echo "row_limit_air: ${ROW_LIMIT_AIR}"
echo "missing_file_mode: ${MISSING_FILE_MODE}"

# Phase 1: Build/refresh v2 location dimensions before any v2 fact loading.
run_step "Populate v2 dim_county" \
  env \
    ACCIDENTS_CSV="${ACCIDENTS_CSV}" \
    AIR_DIR="${AIR_DIR}" \
    AIR_START_YEAR="${AIR_START_YEAR}" \
    AIR_END_YEAR="${AIR_END_YEAR}" \
    RULES_JSON="${RULES_JSON}" \
    PROGRESS_EVERY_ACCIDENTS="${PROGRESS_EVERY_ACCIDENTS}" \
    PROGRESS_EVERY_AIR="${PROGRESS_EVERY_AIR}" \
    TOP_ISSUES="${TOP_ISSUES}" \
    "${ROOT_DIR}/scripts/etl/populate-v2-dim-county.sh"

run_step "Populate v2 dim_streetcity" \
  env \
    PROGRESS_EVERY="${PROGRESS_EVERY_ACCIDENTS}" \
    "${ROOT_DIR}/scripts/etl/populate-v2-dim-streetcity.sh" \
    "${ACCIDENTS_CSV}"

if [[ "${RUN_FACT_ACCIDENT_V2}" == "1" ]]; then
  # Phase 2: Load v2 accident fact after both location dimensions are ready.
  run_step "Populate v2 fact_accident_v2" \
    env \
      PROGRESS_EVERY="${PROGRESS_EVERY_ACCIDENTS}" \
      ROW_LIMIT="${ROW_LIMIT_ACCIDENTS}" \
      "${ROOT_DIR}/scripts/etl/populate-v2-fact-accident.sh" \
      "${ACCIDENTS_CSV}"
else
  echo
  echo "Skipping v2 accident fact load (RUN_FACT_ACCIDENT_V2=${RUN_FACT_ACCIDENT_V2})."
fi

if [[ "${RUN_FACT_AIR_V2}" == "1" ]]; then
  # Phase 3: Load v2 air fact per year to keep progress and failure scope explicit.
  echo
  echo "=== Populate v2 fact_air_quality_daily_v2 (all years) ==="
  echo "started_at: $(date -Iseconds)"
  for year in $(seq "${AIR_START_YEAR}" "${AIR_END_YEAR}"); do
    csv_file="${AIR_DIR}/daily_aqi_by_county_${year}.csv"
    if [[ ! -f "${csv_file}" ]]; then
      echo "status: missing_file (${csv_file})"
      if [[ "${MISSING_FILE_MODE}" == "error" ]]; then
        echo "ERROR: required file missing and MISSING_FILE_MODE=error"
        exit 1
      fi
      continue
    fi
    echo
    echo "---- year ${year} ----"
    env \
      PROGRESS_EVERY="${PROGRESS_EVERY_AIR}" \
      ROW_LIMIT="${ROW_LIMIT_AIR}" \
      TOP_ISSUES="${TOP_ISSUES}" \
      RULES_JSON="${RULES_JSON}" \
      "${ROOT_DIR}/scripts/etl/populate-v2-fact-air-quality-daily.sh" \
      "${csv_file}"
  done
  echo "finished_at: $(date -Iseconds)"
else
  echo
  echo "Skipping v2 air fact load (RUN_FACT_AIR_V2=${RUN_FACT_AIR_V2})."
fi

# Final phase: emit run-level timing and log-file pointer for post-run review.
RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"
echo
echo "V2 ETL runner completed"
echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
echo "log_file: ${LOG_FILE}"
