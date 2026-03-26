#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANALYSIS_JSON="${ROOT_DIR}/docs/analysis.json"
OUT_JSON="${ROOT_DIR}/docs/analysis_validation.json"
SHOW_CHECKED="${SHOW_CHECKED:-none}"

if [[ ! -f "${ANALYSIS_JSON}" ]]; then
  echo "ERROR: analysis JSON not found: ${ANALYSIS_JSON}"
  exit 1
fi

RUN_START_EPOCH="$(date +%s)"
RUN_START_HUMAN="$(date -Iseconds)"

echo "DB vs analysis validation"
echo "started_at: ${RUN_START_HUMAN}"
echo "analysis_json: ${ANALYSIS_JSON}"
echo "output_json: ${OUT_JSON}"
echo "show_checked: ${SHOW_CHECKED}"

python "${ROOT_DIR}/scripts/analysis/analysis_metrics.py" validate-db \
  --analysis-json "${ANALYSIS_JSON}" \
  --output-json "${OUT_JSON}" \
  --show-checked "${SHOW_CHECKED}"

RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"

echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
