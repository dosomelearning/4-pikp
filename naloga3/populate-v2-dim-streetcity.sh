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

# Temp TSV produced by Python and fed into COPY.
TMP_VALUES_FILE="$(mktemp)"
trap 'rm -f "${TMP_VALUES_FILE}"' EXIT

echo "Scanning v2 street-city members from: ${RAW_CSV}"
echo "started_at: ${RUN_START_HUMAN}"
echo "Progress interval: every ${PROGRESS_EVERY} rows"

python - "${RAW_CSV}" "${PROGRESS_EVERY}" <<'PY' > "${TMP_VALUES_FILE}"
import csv
import hashlib
import re
import sys

csv_path = sys.argv[1]
progress_every = int(sys.argv[2])

space_re = re.compile(r"\s+")


# Shared canonicalization helpers keep NK construction deterministic.
def canon(raw):
    if raw is None:
        return None
    cleaned = space_re.sub(" ", raw.strip())
    return cleaned if cleaned else None


def normalize_state_code(raw):
    value = canon(raw)
    return value.upper() if value else None


def normalize_country_code(raw):
    value = canon(raw)
    return value.upper() if value else None


def normalize_county_name(raw):
    value = canon(raw)
    if value is None:
        return None
    words = value.split(" ")
    out = []
    for w in words:
        wl = w.lower()
        if wl in ("st", "st."):
            out.append("Saint")
        elif wl in ("ste", "ste."):
            out.append("Sainte")
        else:
            out.append(w)
    return " ".join(out)


def county_nk(county_name, state_code, country_code):
    return "C|" + "|".join([county_name, state_code, country_code])


# streetcity_nk is a deterministic hash key by architecture contract.
def streetcity_nk(street, city, zipcode, timezone_name, county_nk_value):
    raw = "\x1f".join([street or "", city or "", zipcode or "", timezone_name or "", county_nk_value])
    digest = hashlib.sha1(raw.encode("utf-8")).hexdigest()
    return f"SC|{digest}"


def tsv(value):
    if value is None:
        return r"\N"
    return str(value).replace("\t", " ").replace("\n", " ").replace("\r", " ")


rows = 0
staged = {}
skipped_missing_county = 0

# Single pass over accidents: derive unique street-city records under county_nk.
with open(csv_path, newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows += 1

        county_name = normalize_county_name(row.get("County"))
        state_code = normalize_state_code(row.get("State"))
        country_code = normalize_country_code(row.get("Country"))
        if county_name is None or state_code is None or country_code is None:
            skipped_missing_county += 1
            continue

        county_nk_value = county_nk(county_name, state_code, country_code)
        street = canon(row.get("Street"))
        city = canon(row.get("City"))
        zipcode = canon(row.get("Zipcode"))
        timezone_name = canon(row.get("Timezone"))

        nk = streetcity_nk(street, city, zipcode, timezone_name, county_nk_value)
        if nk not in staged:
            staged[nk] = (county_nk_value, street, city, zipcode, timezone_name)

        if progress_every > 0 and rows % progress_every == 0:
            print(
                (
                    f"[progress] rows={rows:,} streetcity_members={len(staged):,} "
                    f"skipped_missing_county={skipped_missing_county:,}"
                ),
                file=sys.stderr,
                flush=True,
            )

print(
    (
        f"[summary] rows={rows:,} streetcity_members={len(staged):,} "
        f"skipped_missing_county={skipped_missing_county:,}"
    ),
    file=sys.stderr,
    flush=True,
)

for nk in sorted(staged.keys()):
    county_nk_value, street, city, zipcode, timezone_name = staged[nk]
    print(
        "\t".join(
            [
                tsv(nk),
                tsv(county_nk_value),
                tsv(street),
                tsv(city),
                tsv(zipcode),
                tsv(timezone_name),
            ]
        )
    )
PY

if [[ ! -s "${TMP_VALUES_FILE}" ]]; then
  echo "ERROR: no v2 street-city rows extracted from ${RAW_CSV}"
  exit 1
fi

# Stage + FK-resolve check + idempotent insert into dw.dim_streetcity.
{
  cat <<'SQL'
CREATE TEMP TABLE stg_dim_streetcity_v2 (
    streetcity_nk text PRIMARY KEY,
    county_nk     text NOT NULL,
    street        text,
    city          text,
    zipcode       text,
    timezone_name text
);
COPY stg_dim_streetcity_v2 (
    streetcity_nk,
    county_nk,
    street,
    city,
    zipcode,
    timezone_name
) FROM STDIN WITH (FORMAT text, DELIMITER E'\t', NULL '\N');
SQL
  cat "${TMP_VALUES_FILE}"
  cat <<'SQL'
\.

SELECT
  COUNT(*) AS staged_rows,
  COUNT(*) FILTER (WHERE dc.county_key IS NULL) AS unresolved_county_fk
FROM stg_dim_streetcity_v2 s
LEFT JOIN dw.dim_county dc
  ON dc.county_nk = s.county_nk
 AND dc.is_current = TRUE;

INSERT INTO dw.dim_streetcity (
    streetcity_nk,
    county_key,
    street,
    city,
    zipcode,
    timezone_name,
    valid_from,
    valid_to,
    is_current
)
SELECT
    s.streetcity_nk,
    dc.county_key,
    s.street,
    s.city,
    s.zipcode,
    s.timezone_name,
    NOW() AS valid_from,
    TIMESTAMP '9999-12-31 23:59:59' AS valid_to,
    TRUE AS is_current
FROM stg_dim_streetcity_v2 s
JOIN dw.dim_county dc
  ON dc.county_nk = s.county_nk
 AND dc.is_current = TRUE
LEFT JOIN dw.dim_streetcity d
  ON d.streetcity_nk = s.streetcity_nk
 AND d.is_current = TRUE
WHERE d.streetcity_key IS NULL;

DROP TABLE stg_dim_streetcity_v2;
SQL
} | docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -v ON_ERROR_STOP=1"

echo "Done. Current v2 street-city cardinality:"
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -c \"
    SELECT
      COUNT(*) AS dim_streetcity_rows,
      COUNT(*) FILTER (WHERE is_current) AS current_rows
    FROM dw.dim_streetcity;
  \""

RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"
echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
