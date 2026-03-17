#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RAW_CSV="${1:-${ROOT_DIR}/raw/archive/US_Accidents_March23.csv}"
MAX_SAMPLES="${MAX_SAMPLES:-40}"
ROW_LIMIT="${ROW_LIMIT:-0}"
PROGRESS_EVERY="${PROGRESS_EVERY:-250000}"

if [[ ! -f "${RAW_CSV}" ]]; then
  echo "ERROR: raw accidents CSV not found: ${RAW_CSV}"
  exit 1
fi

echo "Inspecting weather-based fact skips"
echo "raw_csv: ${RAW_CSV}"
echo "max_samples: ${MAX_SAMPLES}"
if [[ "${ROW_LIMIT}" != "0" ]]; then
  echo "row_limit: ${ROW_LIMIT}"
fi
echo "progress_every: ${PROGRESS_EVERY}"

python - "${RAW_CSV}" "${MAX_SAMPLES}" "${ROW_LIMIT}" "${PROGRESS_EVERY}" <<'PY'
import csv
import re
import sys
from collections import Counter
from datetime import datetime

csv_path = sys.argv[1]
max_samples = int(sys.argv[2])
row_limit = int(sys.argv[3])
progress_every = int(sys.argv[4])

space_re = re.compile(r"\s+")
ts_head_re = re.compile(r"^(\d{4}[-/]\d{2}[-/]\d{2} \d{2}:\d{2}:\d{2})(?:\.(\d+))?")

true_values = {"1", "true", "t", "yes", "y"}
road_flag_cols = [
    "Amenity", "Bump", "Crossing", "Give_Way", "Junction", "No_Exit",
    "Railway", "Roundabout", "Station", "Stop", "Traffic_Calming",
    "Traffic_Signal", "Turning_Loop",
]

def canon(raw):
    if raw is None:
        return None
    cleaned = space_re.sub(" ", raw.strip())
    return cleaned if cleaned else None

def as_float(raw):
    if raw is None:
        return None
    s = raw.strip()
    if s == "":
        return None
    return float(s)

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
eligible = 0
weather_skips = 0
sampled = 0

by_state = Counter()
by_source = Counter()
by_year = Counter()

with open(csv_path, newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows += 1
        if row_limit > 0 and rows > row_limit:
            break

        source_id = canon(row.get("ID"))
        if source_id is None:
            continue

        sev_raw = canon(row.get("Severity"))
        try:
            severity_level = int(sev_raw) if sev_raw is not None else None
        except ValueError:
            severity_level = None
        if severity_level is None or severity_level <= 0:
            continue

        start_dt = parse_ts(row.get("Start_Time"))
        end_dt = parse_ts(row.get("End_Time"))
        if start_dt is None or end_dt is None or end_dt < start_dt:
            continue

        try:
            start_lat = as_float(row.get("Start_Lat"))
            start_lng = as_float(row.get("Start_Lng"))
        except ValueError:
            continue
        if start_lat is None or start_lng is None:
            continue
        if not (-90 <= start_lat <= 90 and -180 <= start_lng <= 180):
            continue

        street = canon(row.get("Street"))
        city = canon(row.get("City"))
        county = canon(row.get("County"))
        state = canon(row.get("State"))
        zipcode = canon(row.get("Zipcode"))
        country = canon(row.get("Country"))
        timezone = canon(row.get("Timezone"))
        if not any(v is not None for v in (street, city, county, state, zipcode, country, timezone)):
            continue
        if not any(v is not None for v in (county, state, country)):
            continue

        # Equivalent to "would reach weather check in fact ETL".
        eligible += 1
        weather_raw = canon(row.get("Weather_Condition"))
        if weather_raw is not None:
            continue

        weather_skips += 1
        by_state[state or "<NULL>"] += 1
        by_source[canon(row.get("Source")) or "<NULL>"] += 1
        by_year[str(start_dt.year)] += 1

        if sampled < max_samples:
            sampled += 1
            print(
                f"[sample] row={rows} id={source_id} source={repr(canon(row.get('Source')))} "
                f"state={repr(state)} county={repr(county)} start={repr((row.get('Start_Time') or '').strip())} "
                f"end={repr((row.get('End_Time') or '').strip())}"
            )

        if progress_every > 0 and rows % progress_every == 0:
            print(
                f"[progress] rows={rows:,} eligible={eligible:,} weather_skips={weather_skips:,}",
                file=sys.stderr,
                flush=True,
            )

print()
print(f"[summary] rows_scanned={rows:,} eligible_before_weather={eligible:,} weather_skips={weather_skips:,}")

def print_top(counter, label, limit=15):
    print(f"[top_{label}]")
    for key, cnt in counter.most_common(limit):
        print(f"  {cnt:>8}  {key}")

print_top(by_state, "states")
print_top(by_source, "sources")
print_top(by_year, "years")
PY
