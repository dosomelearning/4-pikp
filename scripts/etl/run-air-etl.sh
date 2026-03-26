#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${ROOT_DIR}/docs/logs"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${LOG_DIR}/air_etl_${TIMESTAMP}.log"

RAW_CSV="${RAW_CSV:-${ROOT_DIR}/raw/daily_aqi_by_county_2017.csv}"
PROGRESS_EVERY="${PROGRESS_EVERY:-5000}"
ROW_LIMIT="${ROW_LIMIT:-0}"
RUN_FACT="${RUN_FACT:-0}"
TOP_ISSUES="${TOP_ISSUES:-10}"

mkdir -p "${LOG_DIR}"

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

echo "Air-quality ETL runner"
echo "started_at: ${RUN_START_HUMAN}"
echo "log_file: ${LOG_FILE}"
echo "raw_csv: ${RAW_CSV}"
echo "progress_every: ${PROGRESS_EVERY}"
echo "row_limit_fact: ${ROW_LIMIT}"
echo "run_fact: ${RUN_FACT}"
echo "top_issues: ${TOP_ISSUES}"

run_step "Populate dim_location (air county keys)" \
  env PROGRESS_EVERY="${PROGRESS_EVERY}" TOP_ISSUES="${TOP_ISSUES}" \
  "${ROOT_DIR}/scripts/etl/populate-air-dim-location.sh" \
  "${RAW_CSV}"

run_step "Populate dim_aqi_category" \
  env PROGRESS_EVERY="${PROGRESS_EVERY}" \
  "${ROOT_DIR}/scripts/etl/populate-air-dim-aqi-category.sh" \
  "${RAW_CSV}"

run_step "Populate dim_defining_parameter" \
  env PROGRESS_EVERY="${PROGRESS_EVERY}" \
  "${ROOT_DIR}/scripts/etl/populate-air-dim-defining-parameter.sh" \
  "${RAW_CSV}"

run_step "Check air dimensions" \
  "${ROOT_DIR}/scripts/etl/check-air-dimensions.sh" \
  "${RAW_CSV}"

if [[ "${RUN_FACT}" == "1" ]]; then
  run_step "Populate fact_air_quality_daily" \
    env PROGRESS_EVERY="${PROGRESS_EVERY}" ROW_LIMIT="${ROW_LIMIT}" TOP_ISSUES="${TOP_ISSUES}" \
    "${ROOT_DIR}/scripts/etl/populate-air-fact-daily.sh" \
    "${RAW_CSV}"
else
  echo
  echo "Skipping fact step (RUN_FACT=${RUN_FACT})."
  echo "Set RUN_FACT=1 to execute scripts/etl/populate-air-fact-daily.sh."
fi

RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"
echo
echo "Air-quality ETL runner completed"
echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
echo "log_file: ${LOG_FILE}"
