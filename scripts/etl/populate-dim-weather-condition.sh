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

echo "Scanning weather conditions from: ${RAW_CSV}"
echo "started_at: ${RUN_START_HUMAN}"
echo "Progress interval: every ${PROGRESS_EVERY} rows"

python - "${RAW_CSV}" "${PROGRESS_EVERY}" <<'PY' > "${TMP_VALUES_FILE}"
import csv
import re
import sys

csv_path = sys.argv[1]
progress_every = int(sys.argv[2])

space_re = re.compile(r"\s+")

def canonical(text: str) -> str:
    return space_re.sub(" ", text.strip())

rows = 0
unique = {}

with open(csv_path, newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows += 1
        raw = row.get("Weather_Condition")
        if raw is None:
            continue
        cleaned = canonical(raw)
        if cleaned == "":
            continue

        # NK is canonical lowercase, name keeps canonical display form.
        nk = cleaned.lower()
        if nk not in unique:
            unique[nk] = cleaned

        if progress_every > 0 and rows % progress_every == 0:
            print(
                f"[progress] rows={rows:,} distinct_conditions={len(unique):,}",
                file=sys.stderr,
                flush=True,
            )

print(
    f"[summary] rows={rows:,} distinct_conditions={len(unique):,}",
    file=sys.stderr,
    flush=True,
)

for nk in sorted(unique.keys()):
    print(f"{nk}\t{unique[nk]}")
PY

if [[ ! -s "${TMP_VALUES_FILE}" ]]; then
  echo "ERROR: no weather conditions extracted from ${RAW_CSV}"
  exit 1
fi

{
  cat <<'SQL'
CREATE TEMP TABLE stg_weather_condition (
    weather_condition_nk text PRIMARY KEY,
    weather_condition_name text NOT NULL
);
COPY stg_weather_condition (
    weather_condition_nk,
    weather_condition_name
) FROM STDIN WITH (FORMAT text, DELIMITER E'\t');
SQL
  cat "${TMP_VALUES_FILE}"
  cat <<'SQL'
\.

INSERT INTO dw.dim_weather_condition (
    weather_condition_nk,
    weather_condition_name,
    valid_from,
    valid_to,
    is_current
)
SELECT
    s.weather_condition_nk,
    s.weather_condition_name,
    NOW() AS valid_from,
    TIMESTAMP '9999-12-31 23:59:59' AS valid_to,
    TRUE AS is_current
FROM stg_weather_condition s
LEFT JOIN dw.dim_weather_condition d
  ON d.weather_condition_nk = s.weather_condition_nk
 AND d.is_current = TRUE
WHERE d.weather_condition_nk IS NULL;

-- Ensure explicit unknown member exists for fact rows with missing weather.
INSERT INTO dw.dim_weather_condition (
    weather_condition_nk,
    weather_condition_name,
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
    FROM dw.dim_weather_condition d
    WHERE d.weather_condition_nk = 'unknown'
      AND d.is_current = TRUE
);

DROP TABLE stg_weather_condition;
SQL
} | docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -v ON_ERROR_STOP=1"

echo "Done. Current weather-condition cardinality:"
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -c 'SELECT COUNT(*) AS dim_weather_condition_rows, COUNT(*) FILTER (WHERE is_current) AS current_rows FROM dw.dim_weather_condition;'"

RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"
echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
