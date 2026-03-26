#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANALYSIS_JSON="${ROOT_DIR}/docs/analysis.json"
RAW_CSV="${1:-${ROOT_DIR}/raw/archive/US_Accidents_March23.csv}"
PROGRESS_EVERY="${PROGRESS_EVERY:-250000}"
TOP_ISSUES="${TOP_ISSUES:-10}"

if [[ ! -f "${RAW_CSV}" ]]; then
  echo "ERROR: raw accidents CSV not found: ${RAW_CSV}"
  exit 1
fi

if [[ ! -f "${ANALYSIS_JSON}" ]]; then
  echo "ERROR: analysis JSON not found: ${ANALYSIS_JSON}"
  exit 1
fi

RUN_START_EPOCH="$(date +%s)"
RUN_START_HUMAN="$(date -Iseconds)"

echo "Accidents raw analysis"
echo "started_at: ${RUN_START_HUMAN}"
echo "analysis_json: ${ANALYSIS_JSON}"
echo "raw_csv: ${RAW_CSV}"
echo "progress_every: ${PROGRESS_EVERY}"
echo "top_issues: ${TOP_ISSUES}"

python "${ROOT_DIR}/scripts/analysis/analysis_metrics.py" analyze-accidents \
  --analysis-json "${ANALYSIS_JSON}" \
  --raw-csv "${RAW_CSV}" \
  --progress-every "${PROGRESS_EVERY}" \
  --top-issues "${TOP_ISSUES}"

RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"

echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
