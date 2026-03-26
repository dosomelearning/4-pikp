#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${ROOT_DIR}/docs/logs"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
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
LOG_FILE="${LOG_DIR}/${LOG_PREFIX}accidents_etl_${TIMESTAMP}.log"

RAW_CSV="${RAW_CSV:-${ROOT_DIR}/raw/archive/US_Accidents_March23.csv}"
PROGRESS_EVERY="${PROGRESS_EVERY:-250000}"
TIME_START="${TIME_START:-2016-01-01 00:00:00}"
TIME_END="${TIME_END:-2026-12-31 23:00:00}"
ROW_LIMIT="${ROW_LIMIT:-0}"

mkdir -p "${LOG_DIR}"

# Mirror all output to both terminal and log file.
exec > >(tee -a "${LOG_FILE}") 2>&1

RUN_START_EPOCH="$(date +%s)"
RUN_START_HUMAN="$(date -Iseconds)"

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

echo "Accidents ETL runner"
echo "started_at: ${RUN_START_HUMAN}"
echo "log_file: ${LOG_FILE}"
echo "correlation_id: ${CORRELATION_ID:-<none>}"
echo "raw_csv: ${RAW_CSV}"
echo "progress_every: ${PROGRESS_EVERY}"
echo "time_range: ${TIME_START} -> ${TIME_END}"
echo "row_limit_fact: ${ROW_LIMIT}"

run_step "Populate dim_time" \
  env PROGRESS_EVERY="${PROGRESS_EVERY}" \
  "${ROOT_DIR}/scripts/etl/populate-dim-time-generate-series.sh" \
  "${TIME_START}" "${TIME_END}"

run_step "Populate dim_severity" \
  env PROGRESS_EVERY="${PROGRESS_EVERY}" \
  "${ROOT_DIR}/scripts/etl/populate-dim-severity.sh" \
  "${RAW_CSV}"

run_step "Populate dim_road_condition" \
  env PROGRESS_EVERY="${PROGRESS_EVERY}" \
  "${ROOT_DIR}/scripts/etl/populate-dim-road-condition.sh" \
  "${RAW_CSV}"

run_step "Populate dim_weather_condition" \
  env PROGRESS_EVERY="${PROGRESS_EVERY}" \
  "${ROOT_DIR}/scripts/etl/populate-dim-weather-condition.sh" \
  "${RAW_CSV}"

run_step "Populate dim_location" \
  env PROGRESS_EVERY="${PROGRESS_EVERY}" \
  "${ROOT_DIR}/scripts/etl/populate-dim-location.sh" \
  "${RAW_CSV}"

run_step "Populate fact_accident" \
  env PROGRESS_EVERY="${PROGRESS_EVERY}" ROW_LIMIT="${ROW_LIMIT}" \
  "${ROOT_DIR}/scripts/etl/populate-fact-accident.sh" \
  "${RAW_CSV}"

RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"
echo
echo "Accidents ETL runner completed"
echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
echo "log_file: ${LOG_FILE}"
