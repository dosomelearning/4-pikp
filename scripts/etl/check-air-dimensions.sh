#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/infra/compose/compose.yml"
ENV_FILE="${ROOT_DIR}/infra/compose/.env"
RAW_CSV="${1:-${ROOT_DIR}/raw/daily_aqi_by_county_2017.csv}"

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

TMP_LOCATION_FILE="$(mktemp)"
trap 'rm -f "${TMP_LOCATION_FILE}"' EXIT

echo "Checking air dimensions against: ${RAW_CSV}"
echo "started_at: ${RUN_START_HUMAN}"

python - "${RAW_CSV}" <<'PY' > "${TMP_LOCATION_FILE}"
import csv
import re
import sys

csv_path = sys.argv[1]
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


seen = set()

with open(csv_path, newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        county_name = canon(get_field(row, ["county Name", "County Name", "county_name"]))
        state_name = canon(get_field(row, ["State Name", "state_name"]))
        state_code = state_name_to_abbrev.get(state_name.lower()) if state_name else None
        if county_name is None or state_code is None:
            continue
        seen.add("C|" + "|".join([county_name, state_code, "US"]))

for nk in sorted(seen):
    print(nk)
PY

{
  cat <<'SQL'
SELECT 'dim_aqi_category_current' AS check_name, COUNT(*)::bigint AS check_value
FROM dw.dim_aqi_category
WHERE is_current = TRUE
UNION ALL
SELECT 'dim_defining_parameter_current', COUNT(*)::bigint
FROM dw.dim_defining_parameter
WHERE is_current = TRUE
UNION ALL
SELECT 'dim_location_county_current', COUNT(*)::bigint
FROM dw.dim_location
WHERE is_current = TRUE
  AND location_nk LIKE 'C|%'
UNION ALL
SELECT 'unknown_aqi_category_present', COUNT(*)::bigint
FROM dw.dim_aqi_category
WHERE is_current = TRUE
  AND aqi_category_nk = 'unknown'
UNION ALL
SELECT 'unknown_defining_parameter_present', COUNT(*)::bigint
FROM dw.dim_defining_parameter
WHERE is_current = TRUE
  AND defining_parameter_nk = 'unknown';
SQL
} | docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -v ON_ERROR_STOP=1"

{
  cat <<'SQL'
SELECT 'dup_current_aqi_category_nk' AS check_name, COUNT(*)::bigint AS check_value
FROM (
  SELECT aqi_category_nk
  FROM dw.dim_aqi_category
  WHERE is_current = TRUE
  GROUP BY aqi_category_nk
  HAVING COUNT(*) > 1
) t
UNION ALL
SELECT 'dup_current_defining_parameter_nk', COUNT(*)::bigint
FROM (
  SELECT defining_parameter_nk
  FROM dw.dim_defining_parameter
  WHERE is_current = TRUE
  GROUP BY defining_parameter_nk
  HAVING COUNT(*) > 1
) t;
SQL
} | docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -v ON_ERROR_STOP=1"

{
  cat <<'SQL'
CREATE TEMP TABLE stg_air_expected_location_nk (
  location_nk text PRIMARY KEY
);
COPY stg_air_expected_location_nk (location_nk) FROM STDIN WITH (FORMAT text);
SQL
  cat "${TMP_LOCATION_FILE}"
  cat <<'SQL'
\.
SELECT
  COUNT(*)::bigint AS expected_county_keys,
  COUNT(*) FILTER (WHERE d.location_key IS NULL)::bigint AS missing_in_dim_location
FROM stg_air_expected_location_nk s
LEFT JOIN dw.dim_location d
  ON d.location_nk = s.location_nk
 AND d.is_current = TRUE;
DROP TABLE stg_air_expected_location_nk;
SQL
} | docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -v ON_ERROR_STOP=1"

RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"
echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
