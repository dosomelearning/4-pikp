#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/infra/compose/compose.yml"
ENV_FILE="${ROOT_DIR}/infra/compose/.env"
RAW_CSV="${1:-${ROOT_DIR}/raw/archive/US_Accidents_March23.csv}"
PROGRESS_EVERY="${PROGRESS_EVERY:-250000}"
ROW_LIMIT="${ROW_LIMIT:-0}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: env file not found: ${ENV_FILE}"
  exit 1
fi

if [[ ! -f "${RAW_CSV}" ]]; then
  echo "ERROR: raw accidents CSV not found: ${RAW_CSV}"
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a

: "${POSTGRES_DB:?POSTGRES_DB is required}"
: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"

RUN_START_EPOCH="$(date +%s)"
RUN_START_HUMAN="$(date -Iseconds)"

echo "Loading dw.fact_accident from: ${RAW_CSV}"
echo "started_at: ${RUN_START_HUMAN}"
echo "Progress interval: every ${PROGRESS_EVERY} rows"
if [[ "${ROW_LIMIT}" != "0" ]]; then
  echo "Row limit: ${ROW_LIMIT}"
fi

{
  cat <<'SQL'
CREATE TEMP TABLE stg_fact_accident (
    source_accident_id         text,
    start_time_key             integer,
    end_time_key               integer,
    location_nk                text,
    county_location_nk         text,
    weather_condition_nk       text,
    road_condition_nk          text,
    severity_level             integer,
    start_time                 timestamp,
    end_time                   timestamp,
    accident_duration_minutes  numeric(12,2),
    road_affected_length_mi    numeric(10,2),
    start_latitude             numeric(9,6),
    start_longitude            numeric(9,6),
    end_latitude               numeric(9,6),
    end_longitude              numeric(9,6)
);
COPY stg_fact_accident (
    source_accident_id,
    start_time_key,
    end_time_key,
    location_nk,
    county_location_nk,
    weather_condition_nk,
    road_condition_nk,
    severity_level,
    start_time,
    end_time,
    accident_duration_minutes,
    road_affected_length_mi,
    start_latitude,
    start_longitude,
    end_latitude,
    end_longitude
) FROM STDIN WITH (FORMAT text, DELIMITER E'\t', NULL '\N');
SQL

  python - "${RAW_CSV}" "${PROGRESS_EVERY}" "${ROW_LIMIT}" <<'PY'
import csv
import re
import sys
from datetime import datetime

csv_path = sys.argv[1]
progress_every = int(sys.argv[2])
row_limit = int(sys.argv[3])

space_re = re.compile(r"\s+")
ts_head_re = re.compile(r"^(\d{4}[-/]\d{2}[-/]\d{2} \d{2}:\d{2}:\d{2})(?:\.(\d+))?")
true_values = {"1", "true", "t", "yes", "y"}

road_flag_cols = [
    "Amenity",
    "Bump",
    "Crossing",
    "Give_Way",
    "Junction",
    "No_Exit",
    "Railway",
    "Roundabout",
    "Station",
    "Stop",
    "Traffic_Calming",
    "Traffic_Signal",
    "Turning_Loop",
]


def canon(raw):
    if raw is None:
        return None
    cleaned = space_re.sub(" ", raw.strip())
    return cleaned if cleaned else None


def as_bool(raw):
    if raw is None:
        return False
    s = raw.strip().lower()
    if s == "":
        return False
    return s in true_values


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
            # Python %f supports up to 6 digits (microseconds). Truncate longer tails.
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


def tsv(value):
    if value is None:
        return r"\N"
    text = str(value)
    return text.replace("\t", " ").replace("\n", " ").replace("\r", " ")


rows = 0
emitted = 0
skipped = 0
skip_reason = {
    "missing_id": 0,
    "severity": 0,
    "time_parse": 0,
    "time_order": 0,
    "coords": 0,
    "location_detail": 0,
    "location_county": 0,
    "weather_missing_mapped_unknown": 0,
}

with open(csv_path, newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows += 1
        if row_limit > 0 and rows > row_limit:
            break

        source_id = canon(row.get("ID"))
        if source_id is None:
            skipped += 1
            skip_reason["missing_id"] += 1
            continue

        sev_raw = canon(row.get("Severity"))
        try:
            severity_level = int(sev_raw) if sev_raw is not None else None
        except ValueError:
            severity_level = None
        if severity_level is None or severity_level <= 0:
            skipped += 1
            skip_reason["severity"] += 1
            continue

        start_dt = parse_ts(row.get("Start_Time"))
        end_dt = parse_ts(row.get("End_Time"))
        if start_dt is None or end_dt is None:
            skipped += 1
            skip_reason["time_parse"] += 1
            continue
        if end_dt < start_dt:
            skipped += 1
            skip_reason["time_order"] += 1
            continue

        try:
            start_lat = as_float(row.get("Start_Lat"))
            start_lng = as_float(row.get("Start_Lng"))
            end_lat = as_float(row.get("End_Lat"))
            end_lng = as_float(row.get("End_Lng"))
        except ValueError:
            skipped += 1
            skip_reason["coords"] += 1
            continue

        if start_lat is None or start_lng is None:
            skipped += 1
            skip_reason["coords"] += 1
            continue
        if not (-90 <= start_lat <= 90 and -180 <= start_lng <= 180):
            skipped += 1
            skip_reason["coords"] += 1
            continue
        if end_lat is not None and not (-90 <= end_lat <= 90):
            end_lat = None
        if end_lng is not None and not (-180 <= end_lng <= 180):
            end_lng = None

        street = canon(row.get("Street"))
        city = canon(row.get("City"))
        county = canon(row.get("County"))
        state = canon(row.get("State"))
        zipcode = canon(row.get("Zipcode"))
        country = canon(row.get("Country"))
        timezone = canon(row.get("Timezone"))

        if not any(v is not None for v in (street, city, county, state, zipcode, country, timezone)):
            skipped += 1
            skip_reason["location_detail"] += 1
            continue

        if not any(v is not None for v in (county, state, country)):
            skipped += 1
            skip_reason["location_county"] += 1
            continue

        location_nk = "D|" + "|".join([
            street or "",
            city or "",
            county or "",
            state or "",
            zipcode or "",
            country or "",
            timezone or "",
        ])
        county_location_nk = "C|" + "|".join([
            county or "",
            state or "",
            country or "",
        ])

        weather_raw = canon(row.get("Weather_Condition"))
        if weather_raw is None:
            weather_nk = "unknown"
            skip_reason["weather_missing_mapped_unknown"] += 1
        else:
            weather_nk = weather_raw.lower()

        road_bits = ["1" if as_bool(row.get(col)) else "0" for col in road_flag_cols]
        road_nk = "|".join(road_bits)

        start_key = int(f"{start_dt.year:04d}{start_dt.month:02d}{start_dt.day:02d}{start_dt.hour:02d}")
        end_key = int(f"{end_dt.year:04d}{end_dt.month:02d}{end_dt.day:02d}{end_dt.hour:02d}")
        duration_min = round((end_dt - start_dt).total_seconds() / 60.0, 2)

        try:
            distance_mi = as_float(row.get("Distance(mi)"))
        except ValueError:
            distance_mi = None
        if distance_mi is not None and distance_mi < 0:
            distance_mi = None

        out = [
            source_id,
            start_key,
            end_key,
            location_nk,
            county_location_nk,
            weather_nk,
            road_nk,
            severity_level,
            start_dt.strftime("%Y-%m-%d %H:%M:%S"),
            end_dt.strftime("%Y-%m-%d %H:%M:%S"),
            f"{duration_min:.2f}",
            None if distance_mi is None else f"{distance_mi:.2f}",
            f"{start_lat:.6f}",
            f"{start_lng:.6f}",
            None if end_lat is None else f"{end_lat:.6f}",
            None if end_lng is None else f"{end_lng:.6f}",
        ]
        print("\t".join(tsv(v) for v in out))
        emitted += 1

        if progress_every > 0 and rows % progress_every == 0:
            print(
                f"[progress] rows={rows:,} staged={emitted:,} skipped={skipped:,}",
                file=sys.stderr,
                flush=True,
            )

print(
    f"[summary] rows={rows:,} staged={emitted:,} skipped={skipped:,}",
    file=sys.stderr,
    flush=True,
)
for k in sorted(skip_reason.keys()):
    print(f"[skip_reason] {k}={skip_reason[k]:,}", file=sys.stderr, flush=True)
PY

  cat <<'SQL'
\.

INSERT INTO dw.fact_accident (
    source_accident_id,
    start_time_key,
    end_time_key,
    location_key,
    county_location_key,
    weather_condition_key,
    road_condition_key,
    severity_key,
    start_time,
    end_time,
    accident_duration_minutes,
    road_affected_length_mi,
    start_latitude,
    start_longitude,
    end_latitude,
    end_longitude
)
SELECT
    s.source_accident_id,
    s.start_time_key,
    s.end_time_key,
    dl.location_key,
    cl.location_key,
    wc.weather_condition_key,
    rc.road_condition_key,
    sv.severity_key,
    s.start_time,
    s.end_time,
    s.accident_duration_minutes,
    s.road_affected_length_mi,
    s.start_latitude,
    s.start_longitude,
    s.end_latitude,
    s.end_longitude
FROM stg_fact_accident s
JOIN dw.dim_location dl
  ON dl.location_nk = s.location_nk
 AND dl.is_current = TRUE
JOIN dw.dim_location cl
  ON cl.location_nk = s.county_location_nk
 AND cl.is_current = TRUE
JOIN dw.dim_weather_condition wc
  ON wc.weather_condition_nk = s.weather_condition_nk
 AND wc.is_current = TRUE
JOIN dw.dim_road_condition rc
  ON rc.road_condition_nk = s.road_condition_nk
 AND rc.is_current = TRUE
JOIN dw.dim_severity sv
  ON sv.severity_level = s.severity_level
 AND sv.is_current = TRUE
ON CONFLICT (source_accident_id) DO NOTHING;

DROP TABLE stg_fact_accident;
SQL
} | docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -v ON_ERROR_STOP=1"

echo "Done. Current fact cardinality:"
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -c 'SELECT COUNT(*) AS fact_accident_rows FROM dw.fact_accident;'"

RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"
echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
