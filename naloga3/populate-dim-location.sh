#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/infra/compose/compose.yml"
ENV_FILE="${ROOT_DIR}/infra/compose/.env"
RAW_CSV="${1:-${ROOT_DIR}/raw/archive/US_Accidents_March23.csv}"
PROGRESS_EVERY="${PROGRESS_EVERY:-250000}"

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

TMP_VALUES_FILE="$(mktemp)"
trap 'rm -f "${TMP_VALUES_FILE}"' EXIT

echo "Scanning locations from: ${RAW_CSV}"
echo "started_at: ${RUN_START_HUMAN}"
echo "Progress interval: every ${PROGRESS_EVERY} rows"

python - "${RAW_CSV}" "${PROGRESS_EVERY}" <<'PY' > "${TMP_VALUES_FILE}"
import csv
import re
import sys

csv_path = sys.argv[1]
progress_every = int(sys.argv[2])

space_re = re.compile(r"\s+")

def canon(raw):
    if raw is None:
        return None
    cleaned = space_re.sub(" ", raw.strip())
    return cleaned if cleaned else None

def tsv(value):
    if value is None:
        return r"\N"
    return value.replace("\t", " ").replace("\n", " ").replace("\r", " ")

rows = 0
detail = {}
county = {}

with open(csv_path, newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows += 1

        street = canon(row.get("Street"))
        city = canon(row.get("City"))
        county_name = canon(row.get("County"))
        state_code = canon(row.get("State"))
        zipcode = canon(row.get("Zipcode"))
        country_code = canon(row.get("Country"))
        timezone_name = canon(row.get("Timezone"))

        # Detailed location member.
        if any(v is not None for v in (street, city, county_name, state_code, zipcode, country_code, timezone_name)):
            dnk = "D|" + "|".join([
                street or "",
                city or "",
                county_name or "",
                state_code or "",
                zipcode or "",
                country_code or "",
                timezone_name or "",
            ])
            if dnk not in detail:
                detail[dnk] = (street, city, county_name, state_code, zipcode, country_code, timezone_name)

        # County-level conformed member for cross-source joins.
        if any(v is not None for v in (county_name, state_code, country_code)):
            cnk = "C|" + "|".join([
                county_name or "",
                state_code or "",
                country_code or "",
            ])
            if cnk not in county:
                county[cnk] = (None, None, county_name, state_code, None, country_code, None)

        if progress_every > 0 and rows % progress_every == 0:
            print(
                f"[progress] rows={rows:,} detail={len(detail):,} county={len(county):,} total={len(detail)+len(county):,}",
                file=sys.stderr,
                flush=True,
            )

print(
    f"[summary] rows={rows:,} detail={len(detail):,} county={len(county):,} total={len(detail)+len(county):,}",
    file=sys.stderr,
    flush=True,
)

for nk, cols in sorted(detail.items()):
    print("\t".join([tsv(nk)] + [tsv(v) for v in cols]))

for nk, cols in sorted(county.items()):
    print("\t".join([tsv(nk)] + [tsv(v) for v in cols]))
PY

if [[ ! -s "${TMP_VALUES_FILE}" ]]; then
  echo "ERROR: no locations extracted from ${RAW_CSV}"
  exit 1
fi

{
  cat <<'SQL'
CREATE TEMP TABLE stg_location (
    location_nk text PRIMARY KEY,
    street text,
    city text,
    county text,
    state_code text,
    zipcode text,
    country_code text,
    timezone_name text
);
COPY stg_location (
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
FROM stg_location s
LEFT JOIN dw.dim_location d
  ON d.location_nk = s.location_nk
 AND d.is_current = TRUE
WHERE d.location_nk IS NULL;

DROP TABLE stg_location;
SQL
} | docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -v ON_ERROR_STOP=1"

echo "Done. Current location cardinality:"
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -c 'SELECT COUNT(*) AS dim_location_rows, COUNT(*) FILTER (WHERE is_current) AS current_rows FROM dw.dim_location;'"

RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"
echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
