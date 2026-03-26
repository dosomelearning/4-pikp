#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/infra/compose/compose.yml"
ENV_FILE="${ROOT_DIR}/infra/compose/.env"
RAW_CSV="${1:-${ROOT_DIR}/raw/daily_aqi_by_county_2017.csv}"
PROGRESS_EVERY="${PROGRESS_EVERY:-250000}"

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

TMP_VALUES_FILE="$(mktemp)"
trap 'rm -f "${TMP_VALUES_FILE}"' EXIT

echo "Scanning county-level air locations from: ${RAW_CSV}"
echo "started_at: ${RUN_START_HUMAN}"
echo "Progress interval: every ${PROGRESS_EVERY} rows"

python - "${RAW_CSV}" "${PROGRESS_EVERY}" <<'PY' > "${TMP_VALUES_FILE}"
import csv
import re
import sys

csv_path = sys.argv[1]
progress_every = int(sys.argv[2])

space_re = re.compile(r"\s+")

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


def to_state_abbrev(state_name):
    if state_name is None:
        return None
    return state_name_to_abbrev.get(state_name.lower())


def tsv(value):
    if value is None:
        return r"\N"
    return value.replace("\t", " ").replace("\n", " ").replace("\r", " ")


rows = 0
county_members = {}
skipped_missing_county = 0
skipped_unknown_state = 0

with open(csv_path, newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows += 1

        county_name = canon(get_field(row, ["county Name", "County Name", "county_name"]))
        state_name = canon(get_field(row, ["State Name", "state_name"]))
        state_code = to_state_abbrev(state_name)

        if county_name is None:
            skipped_missing_county += 1
            continue
        if state_code is None:
            skipped_unknown_state += 1
            continue

        country_code = "US"
        location_nk = "C|" + "|".join([county_name, state_code, country_code])
        if location_nk not in county_members:
            county_members[location_nk] = (None, None, county_name, state_code, None, country_code, None)

        if progress_every > 0 and rows % progress_every == 0:
            print(
                (
                    f"[progress] rows={rows:,} county_members={len(county_members):,} "
                    f"skipped_missing_county={skipped_missing_county:,} "
                    f"skipped_unknown_state={skipped_unknown_state:,}"
                ),
                file=sys.stderr,
                flush=True,
            )

print(
    (
        f"[summary] rows={rows:,} county_members={len(county_members):,} "
        f"skipped_missing_county={skipped_missing_county:,} "
        f"skipped_unknown_state={skipped_unknown_state:,}"
    ),
    file=sys.stderr,
    flush=True,
)

for nk, cols in sorted(county_members.items()):
    print("\t".join([tsv(nk)] + [tsv(v) for v in cols]))
PY

if [[ ! -s "${TMP_VALUES_FILE}" ]]; then
  echo "ERROR: no county locations extracted from ${RAW_CSV}"
  exit 1
fi

{
  cat <<'SQL'
CREATE TEMP TABLE stg_location_air (
    location_nk text PRIMARY KEY,
    street text,
    city text,
    county text,
    state_code text,
    zipcode text,
    country_code text,
    timezone_name text
);
COPY stg_location_air (
    location_nk,
    street,
    city,
    county,
    state_code,
    zipcode,
    country_code,
    timezone_name
) FROM STDIN WITH (FORMAT text, DELIMITER E'\t', NULL '\N');
SQL
  cat "${TMP_VALUES_FILE}"
  cat <<'SQL'
\.

INSERT INTO dw.dim_location (
    location_nk,
    street,
    city,
    county,
    state_code,
    zipcode,
    country_code,
    timezone_name,
    valid_from,
    valid_to,
    is_current
)
SELECT
    s.location_nk,
    s.street,
    s.city,
    s.county,
    s.state_code,
    s.zipcode,
    s.country_code,
    s.timezone_name,
    NOW() AS valid_from,
    TIMESTAMP '9999-12-31 23:59:59' AS valid_to,
    TRUE AS is_current
FROM stg_location_air s
LEFT JOIN dw.dim_location d
  ON d.location_nk = s.location_nk
 AND d.is_current = TRUE
WHERE d.location_nk IS NULL;

DROP TABLE stg_location_air;
SQL
} | docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -v ON_ERROR_STOP=1"

echo "Done. Current county-level location cardinality:"
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -c \"
    SELECT
      COUNT(*) AS county_rows,
      COUNT(*) FILTER (WHERE is_current) AS county_current_rows
    FROM dw.dim_location
    WHERE location_nk LIKE 'C|%';
  \""

RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"
echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
