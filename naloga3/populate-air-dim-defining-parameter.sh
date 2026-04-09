#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/infra/compose/compose.yml"
ENV_FILE="${ROOT_DIR}/infra/compose/.env"
RAW_CSV="${1:-${ROOT_DIR}/raw/daily_aqi_by_county_2017.csv}"
PROGRESS_EVERY="${PROGRESS_EVERY:-5000}"

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

echo "Scanning defining parameters from: ${RAW_CSV}"
echo "started_at: ${RUN_START_HUMAN}"
echo "Progress interval: every ${PROGRESS_EVERY} rows"

python - "${RAW_CSV}" "${PROGRESS_EVERY}" <<'PY' > "${TMP_VALUES_FILE}"
import csv
import re
import sys

csv_path = sys.argv[1]
progress_every = int(sys.argv[2])

space_re = re.compile(r"\s+")
token_re = re.compile(r"[^a-z0-9]+")
underscore_re = re.compile(r"_+")


def canon(raw):
    if raw is None:
        return None
    cleaned = space_re.sub(" ", raw.strip())
    return cleaned if cleaned else None


def to_nk(text):
    nk = token_re.sub("_", text.lower())
    nk = underscore_re.sub("_", nk).strip("_")
    return nk


rows = 0
unique = {}

with open(csv_path, newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows += 1
        raw = row.get("Defining Parameter")
        cleaned = canon(raw)
        if cleaned is None:
            continue

        nk = to_nk(cleaned)
        if nk == "":
            continue
        if nk not in unique:
            unique[nk] = cleaned

        if progress_every > 0 and rows % progress_every == 0:
            print(
                f"[progress] rows={rows:,} distinct_defining_parameters={len(unique):,}",
                file=sys.stderr,
                flush=True,
            )

print(
    f"[summary] rows={rows:,} distinct_defining_parameters={len(unique):,}",
    file=sys.stderr,
    flush=True,
)

for nk in sorted(unique.keys()):
    print(f"{nk}\t{unique[nk]}")
PY

if [[ ! -s "${TMP_VALUES_FILE}" ]]; then
  echo "ERROR: no defining parameters extracted from ${RAW_CSV}"
  exit 1
fi

{
  cat <<'SQL'
CREATE TEMP TABLE stg_defining_parameter (
    defining_parameter_nk text PRIMARY KEY,
    defining_parameter_name text NOT NULL
);
COPY stg_defining_parameter (
    defining_parameter_nk,
    defining_parameter_name
) FROM STDIN WITH (FORMAT text, DELIMITER E'\t');
SQL
  cat "${TMP_VALUES_FILE}"
  cat <<'SQL'
\.

INSERT INTO dw.dim_defining_parameter (
    defining_parameter_nk,
    defining_parameter_name,
    valid_from,
    valid_to,
    is_current
)
SELECT
    s.defining_parameter_nk,
    s.defining_parameter_name,
    NOW() AS valid_from,
    TIMESTAMP '9999-12-31 23:59:59' AS valid_to,
    TRUE AS is_current
FROM stg_defining_parameter s
LEFT JOIN dw.dim_defining_parameter d
  ON d.defining_parameter_nk = s.defining_parameter_nk
 AND d.is_current = TRUE
WHERE d.defining_parameter_nk IS NULL;

-- Ensure explicit unknown member exists for fact rows with missing parameter.
INSERT INTO dw.dim_defining_parameter (
    defining_parameter_nk,
    defining_parameter_name,
    valid_from,
    valid_to,
    is_current
)
SELECT
    'unknown',
    'Unknown',
    NOW(),
    TIMESTAMP '9999-12-31 23:59:59',
    TRUE
WHERE NOT EXISTS (
    SELECT 1
    FROM dw.dim_defining_parameter d
    WHERE d.defining_parameter_nk = 'unknown'
      AND d.is_current = TRUE
);

DROP TABLE stg_defining_parameter;
SQL
} | docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -v ON_ERROR_STOP=1"

echo "Done. Current defining-parameter cardinality:"
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -c 'SELECT COUNT(*) AS dim_defining_parameter_rows, COUNT(*) FILTER (WHERE is_current) AS current_rows FROM dw.dim_defining_parameter;'"

RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"
echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
