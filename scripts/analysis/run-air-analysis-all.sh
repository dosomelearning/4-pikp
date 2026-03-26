#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANALYSIS_JSON="${ROOT_DIR}/docs/analysis.json"
RAW_DIR="${RAW_DIR:-${ROOT_DIR}/raw}"
AIR_START_YEAR="${AIR_START_YEAR:-2016}"
AIR_END_YEAR="${AIR_END_YEAR:-2023}"
PROGRESS_EVERY="${PROGRESS_EVERY:-50000}"
TOP_ISSUES="${TOP_ISSUES:-10}"

if [[ ! -d "${RAW_DIR}" ]]; then
  echo "ERROR: raw directory not found: ${RAW_DIR}"
  exit 1
fi

if [[ ! -f "${ANALYSIS_JSON}" ]]; then
  echo "ERROR: analysis JSON not found: ${ANALYSIS_JSON}"
  exit 1
fi

if [[ "${AIR_START_YEAR}" -gt "${AIR_END_YEAR}" ]]; then
  echo "ERROR: AIR_START_YEAR must be <= AIR_END_YEAR"
  exit 1
fi

RUN_START_EPOCH="$(date +%s)"
RUN_START_HUMAN="$(date -Iseconds)"

echo "Air raw analysis (all years)"
echo "started_at: ${RUN_START_HUMAN}"
echo "analysis_json: ${ANALYSIS_JSON}"
echo "raw_dir: ${RAW_DIR}"
echo "year_range: ${AIR_START_YEAR}-${AIR_END_YEAR}"
echo "progress_every: ${PROGRESS_EVERY}"
echo "top_issues: ${TOP_ISSUES}"

python "${ROOT_DIR}/scripts/analysis/analysis_metrics.py" analyze-air \
  --analysis-json "${ANALYSIS_JSON}" \
  --raw-dir "${RAW_DIR}" \
  --start-year "${AIR_START_YEAR}" \
  --end-year "${AIR_END_YEAR}" \
  --progress-every "${PROGRESS_EVERY}" \
  --top-issues "${TOP_ISSUES}"

RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"

echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
