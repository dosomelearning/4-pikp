#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANALYSIS_JSON="${ANALYSIS_JSON:-${ROOT_DIR}/docs/analysis.json}"

if [[ ! -f "${ANALYSIS_JSON}" ]]; then
  echo "ERROR: analysis JSON not found: ${ANALYSIS_JSON}"
  exit 1
fi

RUN_START_EPOCH="$(date +%s)"
RUN_START_HUMAN="$(date -Iseconds)"

echo "Analysis JSON clear"
echo "started_at: ${RUN_START_HUMAN}"
echo "analysis_json: ${ANALYSIS_JSON}"

python - "${ANALYSIS_JSON}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
with path.open("r", encoding="utf-8") as f:
    data = json.load(f)

KEEP_ROOT_KEYS = {"schema_version", "note"}

def clear_value(value):
    if isinstance(value, dict):
        return {k: clear_value(v) for k, v in value.items()}
    if isinstance(value, list):
        return []
    if isinstance(value, bool):
        return False
    if isinstance(value, (int, float)):
        return 0
    if isinstance(value, str):
        return None
    return None

cleared = {}
for key, value in data.items():
    if key in KEEP_ROOT_KEYS:
        cleared[key] = value
    else:
        cleared[key] = clear_value(value)

with path.open("w", encoding="utf-8") as f:
    json.dump(cleared, f, indent=2, sort_keys=True)
    f.write("\n")
PY

RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"
echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
