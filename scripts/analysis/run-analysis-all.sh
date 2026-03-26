#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${ROOT_DIR}/docs/logs"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${LOG_DIR}/analysis_all_${TIMESTAMP}.log"

ACCIDENTS_RAW="${ACCIDENTS_RAW:-${ROOT_DIR}/raw/archive/US_Accidents_March23.csv}"
RAW_DIR="${RAW_DIR:-${ROOT_DIR}/raw}"
AIR_START_YEAR="${AIR_START_YEAR:-2016}"
AIR_END_YEAR="${AIR_END_YEAR:-2023}"
ACCIDENTS_PROGRESS_EVERY="${ACCIDENTS_PROGRESS_EVERY:-250000}"
AIR_PROGRESS_EVERY="${AIR_PROGRESS_EVERY:-50000}"
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

echo "Raw analysis runner"
echo "started_at: ${RUN_START_HUMAN}"
echo "log_file: ${LOG_FILE}"
echo "accidents_raw: ${ACCIDENTS_RAW}"
echo "air_raw_dir: ${RAW_DIR}"
echo "air_year_range: ${AIR_START_YEAR}-${AIR_END_YEAR}"
echo "top_issues: ${TOP_ISSUES}"

run_step "Analyze data shape (metadata)" \
  env ACCIDENTS_RAW="${ACCIDENTS_RAW}" RAW_DIR="${RAW_DIR}" \
      AIR_START_YEAR="${AIR_START_YEAR}" AIR_END_YEAR="${AIR_END_YEAR}" \
  "${ROOT_DIR}/scripts/analysis/run-data-shape-analysis.sh"

run_step "Analyze accidents raw" \
  env SKIP_DATA_SHAPE=1 PROGRESS_EVERY="${ACCIDENTS_PROGRESS_EVERY}" TOP_ISSUES="${TOP_ISSUES}" \
  "${ROOT_DIR}/scripts/analysis/run-accidents-analysis.sh" \
  "${ACCIDENTS_RAW}"

run_step "Analyze air raw (all years)" \
  env RAW_DIR="${RAW_DIR}" AIR_START_YEAR="${AIR_START_YEAR}" AIR_END_YEAR="${AIR_END_YEAR}" \
      SKIP_DATA_SHAPE=1 PROGRESS_EVERY="${AIR_PROGRESS_EVERY}" TOP_ISSUES="${TOP_ISSUES}" \
  "${ROOT_DIR}/scripts/analysis/run-air-analysis-all.sh"

RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"

echo
echo "Raw analysis runner completed"
echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
echo "log_file: ${LOG_FILE}"
