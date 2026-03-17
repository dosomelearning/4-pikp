#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RAW_CSV="${1:-${ROOT_DIR}/raw/archive/US_Accidents_March23.csv}"
MAX_SAMPLES="${MAX_SAMPLES:-50}"
ROW_LIMIT="${ROW_LIMIT:-0}"
SHOW_COUNTS="${SHOW_COUNTS:-1}"
SKIP_ROWS="${SKIP_ROWS:-0}"

if [[ ! -f "${RAW_CSV}" ]]; then
  echo "ERROR: raw accidents CSV not found: ${RAW_CSV}"
  exit 1
fi

echo "Inspecting timestamp parse failures"
echo "raw_csv: ${RAW_CSV}"
echo "max_samples: ${MAX_SAMPLES}"
if [[ "${ROW_LIMIT}" != "0" ]]; then
  echo "row_limit: ${ROW_LIMIT}"
fi
if [[ "${SKIP_ROWS}" != "0" ]]; then
  echo "skip_rows: ${SKIP_ROWS}"
fi

python - "${RAW_CSV}" "${MAX_SAMPLES}" "${ROW_LIMIT}" "${SHOW_COUNTS}" "${SKIP_ROWS}" <<'PY'
import csv
import re
import sys
from collections import Counter
from datetime import datetime

csv_path = sys.argv[1]
max_samples = int(sys.argv[2])
row_limit = int(sys.argv[3])
show_counts = int(sys.argv[4]) != 0
skip_rows = int(sys.argv[5])

ts_head_re = re.compile(r"^(\d{4}[-/]\d{2}[-/]\d{2} \d{2}:\d{2}:\d{2})(?:\.(\d+))?")

def parse_ts(raw):
    if raw is None:
        return None
    s = raw.strip()
    if s == "":
        return None

    m = ts_head_re.match(s)
    if m:
        base = m.group(1).replace("/", "-")
        frac = m.group(2)
        if frac:
            frac6 = (frac[:6]).ljust(6, "0")
            s = f"{base}.{frac6}"
        else:
            s = base
    else:
        s = s.replace("/", "-")

    for fmt in ("%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%d %H:%M:%S"):
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            continue
    return None

rows = 0
fail_count = 0
sampled = 0
counter = Counter()

with open(csv_path, newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows += 1
        if skip_rows > 0 and rows <= skip_rows:
            continue
        if row_limit > 0 and rows > row_limit:
            break

        s_raw = row.get("Start_Time")
        e_raw = row.get("End_Time")
        s_ok = parse_ts(s_raw) is not None
        e_ok = parse_ts(e_raw) is not None

        if s_ok and e_ok:
            continue

        fail_count += 1
        reason = []
        if not s_ok:
            reason.append("Start_Time")
            counter[f"Start_Time::{(s_raw or '').strip()}"] += 1
        if not e_ok:
            reason.append("End_Time")
            counter[f"End_Time::{(e_raw or '').strip()}"] += 1

        if sampled < max_samples:
            sampled += 1
            print(
                f"[sample] row={rows} reason={','.join(reason)} start={repr((s_raw or '').strip())} end={repr((e_raw or '').strip())}"
            )

print()
print(f"[summary] rows_scanned={rows:,} parse_fail_rows={fail_count:,}")

if show_counts:
    print("[top_unparsed_values]")
    for key, cnt in counter.most_common(30):
        col, val = key.split("::", 1)
        print(f"  {cnt:>8}  {col}  {repr(val)}")
PY
