#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${ROOT_DIR}/docs/logs"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

RAW_CORRELATION_ID="${CORRELATION_ID:-}"
if [[ -z "${RAW_CORRELATION_ID}" ]]; then
  RAW_CORRELATION_ID="$(printf '%04X' "$((RANDOM % 65536))")"
fi
CORRELATION_ID="$(printf '%s' "${RAW_CORRELATION_ID}" | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z0-9')"
if [[ "${#CORRELATION_ID}" -ne 4 ]]; then
  echo "ERROR: CORRELATION_ID must normalize to exactly 4 alphanumeric chars"
  echo "  provided: ${RAW_CORRELATION_ID}"
  echo "  normalized: ${CORRELATION_ID}"
  exit 1
fi

LOG_FILE="${LOG_DIR}/${CORRELATION_ID}_full_etl_cycle_${TIMESTAMP}.log"
SHOW_CHECKED="${SHOW_CHECKED:-non_compliant}"

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

echo "Full ETL cycle runner"
echo "started_at: ${RUN_START_HUMAN}"
echo "correlation_id: ${CORRELATION_ID}"
echo "show_checked: ${SHOW_CHECKED}"
echo "log_file: ${LOG_FILE}"

run_step "Clear DW tables" \
  "${ROOT_DIR}/scripts/etl/clear-dw-tables.sh"

run_step "Clear analysis JSON" \
  "${ROOT_DIR}/scripts/analysis/analysis_json_clear.sh"

run_step "Run raw analysis (all)" \
  env CORRELATION_ID="${CORRELATION_ID}" \
  "${ROOT_DIR}/scripts/analysis/run-analysis-all.sh"

run_step "Run accidents ETL" \
  env CORRELATION_ID="${CORRELATION_ID}" \
  "${ROOT_DIR}/scripts/etl/run-accidents-etl.sh"

run_step "Run air ETL (all years)" \
  env CORRELATION_ID="${CORRELATION_ID}" \
  "${ROOT_DIR}/scripts/etl/run-air-etl-all.sh"

run_step "Validate DB vs analysis" \
  env SHOW_CHECKED="${SHOW_CHECKED}" \
  "${ROOT_DIR}/scripts/analysis/validate-db-vs-analysis.sh"

RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"

echo
echo "Full ETL cycle runner completed"
echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
echo "correlation_id: ${CORRELATION_ID}"
echo "log_file: ${LOG_FILE}"
