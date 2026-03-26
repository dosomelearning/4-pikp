#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/infra/compose/compose.yml"
ENV_FILE="${ROOT_DIR}/infra/compose/.env"
RAW_CSV="${1:-${ROOT_DIR}/raw/daily_aqi_by_county_2017.csv}"
PROGRESS_EVERY="${PROGRESS_EVERY:-250000}"
ROW_LIMIT="${ROW_LIMIT:-0}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: env file not found: ${ENV_FILE}"
  exit 1
fi

if [[ ! -f "${RAW_CSV}" ]]; then
  echo "ERROR: raw air-quality CSV not found: ${RAW_CSV}"
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

echo "Loading dw.fact_air_quality_daily from: ${RAW_CSV}"
echo "started_at: ${RUN_START_HUMAN}"
echo "Progress interval: every ${PROGRESS_EVERY} rows"
if [[ "${ROW_LIMIT}" != "0" ]]; then
  echo "Row limit: ${ROW_LIMIT}"
fi

{
  cat <<'SQL'
CREATE TEMP TABLE stg_fact_air_quality_daily (
    source_state_code          text,
    source_county_code         text,
    source_date                date,
    time_key                   integer,
    location_nk                text,
    aqi_category_nk            text,
    defining_parameter_nk      text,
    aqi                        integer,
    number_of_sites_reporting  integer,
    defining_site_code         text
);
COPY stg_fact_air_quality_daily (
    source_state_code,
    source_county_code,
    source_date,
    time_key,
    location_nk,
    aqi_category_nk,
    defining_parameter_nk,
    aqi,
    number_of_sites_reporting,
    defining_site_code
) FROM STDIN WITH (FORMAT text, DELIMITER E'\t', NULL '\N');
SQL

  python - "${RAW_CSV}" "${PROGRESS_EVERY}" "${ROW_LIMIT}" <<'PY'
import csv
import datetime
import re
import sys

csv_path = sys.argv[1]
progress_every = int(sys.argv[2])
row_limit = int(sys.argv[3])

space_re = re.compile(r"\s+")
token_re = re.compile(r"[^a-z0-9]+")
underscore_re = re.compile(r"_+")

state_name_to_abbrev = {
    "alabama": "AL", "alaska": "AK", "arizona": "AZ", "arkansas": "AR",
    "california": "CA", "colorado": "CO", "connecticut": "CT", "delaware": "DE",
    "district of columbia": "DC", "florida": "FL", "georgia": "GA", "hawaii": "HI",
    "idaho": "ID", "illinois": "IL", "indiana": "IN", "iowa": "IA", "kansas": "KS",
    "kentucky": "KY", "louisiana": "LA", "maine": "ME", "maryland": "MD",
    "massachusetts": "MA", "michigan": "MI", "minnesota": "MN", "mississippi": "MS",
    "missouri": "MO", "montana": "MT", "nebraska": "NE", "nevada": "NV",
    "new hampshire": "NH", "new jersey": "NJ", "new mexico": "NM", "new york": "NY",
    "north carolina": "NC", "north dakota": "ND", "ohio": "OH", "oklahoma": "OK",
    "oregon": "OR", "pennsylvania": "PA", "rhode island": "RI",
    "south carolina": "SC", "south dakota": "SD", "tennessee": "TN", "texas": "TX",
    "utah": "UT", "vermont": "VT", "virginia": "VA", "washington": "WA",
    "west virginia": "WV", "wisconsin": "WI", "wyoming": "WY",
    "puerto rico": "PR", "guam": "GU", "american samoa": "AS",
    "virgin islands": "VI", "northern mariana islands": "MP",
}


def canon(raw):
    if raw is None:
        return None
    cleaned = space_re.sub(" ", raw.strip())
    return cleaned if cleaned else None


def to_nk(text):
    nk = token_re.sub("_", text.lower())
    nk = underscore_re.sub("_", nk).strip("_")
    return nk


def get_field(row, candidates):
    for key in candidates:
        if key in row:
            return row.get(key)
    lowered = {k.lower(): v for k, v in row.items()}
    for key in candidates:
        v = lowered.get(key.lower())
        if v is not None:
            return v
    return None


def tsv(value):
    if value is None:
        return r"\N"
    return str(value).replace("\t", " ").replace("\n", " ").replace("\r", " ")


rows = 0
staged = 0
skipped = 0
skip_reason = {
    "missing_state_code": 0,
    "missing_county_code": 0,
    "missing_date": 0,
    "invalid_date": 0,
    "missing_county_name": 0,
    "unknown_state_name": 0,
    "invalid_aqi": 0,
    "invalid_sites_reporting": 0,
    "missing_category_mapped_unknown": 0,
    "missing_defining_parameter_mapped_unknown": 0,
}

with open(csv_path, newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows += 1
        if row_limit > 0 and rows > row_limit:
            break

        state_code = canon(row.get("State Code"))
        county_code = canon(row.get("County Code"))
        if state_code is None:
            skipped += 1
            skip_reason["missing_state_code"] += 1
            continue
        if county_code is None:
            skipped += 1
            skip_reason["missing_county_code"] += 1
            continue

        date_raw = canon(row.get("Date"))
        if date_raw is None:
            skipped += 1
            skip_reason["missing_date"] += 1
            continue
        try:
            source_date = datetime.datetime.strptime(date_raw, "%Y-%m-%d").date()
        except ValueError:
            skipped += 1
            skip_reason["invalid_date"] += 1
            continue

        county_name = canon(get_field(row, ["county Name", "County Name", "county_name"]))
        if county_name is None:
            skipped += 1
            skip_reason["missing_county_name"] += 1
            continue

        state_name = canon(get_field(row, ["State Name", "state_name"]))
        state_abbrev = state_name_to_abbrev.get(state_name.lower()) if state_name else None
        if state_abbrev is None:
            skipped += 1
            skip_reason["unknown_state_name"] += 1
            continue

        aqi_raw = canon(row.get("AQI"))
        sites_raw = canon(row.get("Number of Sites Reporting"))
        try:
            aqi = int(aqi_raw) if aqi_raw is not None else None
        except ValueError:
            aqi = None
        try:
            sites = int(sites_raw) if sites_raw is not None else None
        except ValueError:
            sites = None
        if aqi is None or aqi < 0:
            skipped += 1
            skip_reason["invalid_aqi"] += 1
            continue
        if sites is None or sites < 0:
            skipped += 1
            skip_reason["invalid_sites_reporting"] += 1
            continue

        category_name = canon(row.get("Category"))
        if category_name is None:
            category_nk = "unknown"
            skip_reason["missing_category_mapped_unknown"] += 1
        else:
            category_nk = to_nk(category_name)
            if category_nk == "":
                category_nk = "unknown"
                skip_reason["missing_category_mapped_unknown"] += 1

        param_name = canon(row.get("Defining Parameter"))
        if param_name is None:
            parameter_nk = "unknown"
            skip_reason["missing_defining_parameter_mapped_unknown"] += 1
        else:
            parameter_nk = to_nk(param_name)
            if parameter_nk == "":
                parameter_nk = "unknown"
                skip_reason["missing_defining_parameter_mapped_unknown"] += 1

        location_nk = "C|" + "|".join([county_name, state_abbrev, "US"])
        time_key = int(f"{source_date.year:04d}{source_date.month:02d}{source_date.day:02d}00")
        defining_site_code = canon(row.get("Defining Site"))

        out = [
            state_code,
            county_code,
            source_date.isoformat(),
            time_key,
            location_nk,
            category_nk,
            parameter_nk,
            aqi,
            sites,
            defining_site_code,
        ]
        print("\t".join(tsv(v) for v in out))
        staged += 1

        if progress_every > 0 and rows % progress_every == 0:
            print(
                f"[progress] rows={rows:,} staged={staged:,} skipped={skipped:,}",
                file=sys.stderr,
                flush=True,
            )

print(
    f"[summary] rows_scanned={rows:,} staged={staged:,} skipped={skipped:,}",
    file=sys.stderr,
    flush=True,
)
print("[skip_reasons]", file=sys.stderr, flush=True)
for k in sorted(skip_reason.keys()):
    print(f"  - {k}: {skip_reason[k]:,}", file=sys.stderr, flush=True)
PY

  cat <<'SQL'
\.

INSERT INTO dw.fact_air_quality_daily (
    source_state_code,
    source_county_code,
    source_date,
    time_key,
    location_key,
    aqi_category_key,
    defining_parameter_key,
    aqi,
    number_of_sites_reporting,
    defining_site_code
)
SELECT
    s.source_state_code,
    s.source_county_code,
    s.source_date,
    s.time_key,
    dl.location_key,
    ac.aqi_category_key,
    dp.defining_parameter_key,
    s.aqi,
    s.number_of_sites_reporting,
    s.defining_site_code
FROM stg_fact_air_quality_daily s
JOIN dw.dim_time dt
  ON dt.time_key = s.time_key
JOIN dw.dim_location dl
  ON dl.location_nk = s.location_nk
 AND dl.is_current = TRUE
JOIN dw.dim_aqi_category ac
  ON ac.aqi_category_nk = s.aqi_category_nk
 AND ac.is_current = TRUE
JOIN dw.dim_defining_parameter dp
  ON dp.defining_parameter_nk = s.defining_parameter_nk
 AND dp.is_current = TRUE
ON CONFLICT (source_state_code, source_county_code, source_date) DO NOTHING;

DROP TABLE stg_fact_air_quality_daily;
SQL
} | docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -v ON_ERROR_STOP=1"

echo "Done. Current air-fact cardinality:"
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -c 'SELECT COUNT(*) AS fact_air_quality_daily_rows FROM dw.fact_air_quality_daily;'"

RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"
echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
