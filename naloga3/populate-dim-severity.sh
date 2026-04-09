#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/infra/compose/compose.yml"
ENV_FILE="${ROOT_DIR}/infra/compose/.env"
RAW_CSV="${1:-${ROOT_DIR}/raw/archive/US_Accidents_March23.csv}"

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

python - "${RAW_CSV}" <<'PY' > "${TMP_VALUES_FILE}"
import csv
import sys

csv_path = sys.argv[1]
vals = set()

with open(csv_path, newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        raw = (row.get("Severity") or "").strip()
        if not raw:
            continue
        try:
            sev = int(raw)
        except ValueError:
            continue
        if sev > 0:
            vals.add(sev)

for sev in sorted(vals):
    print(sev)
PY

if [[ ! -s "${TMP_VALUES_FILE}" ]]; then
  echo "ERROR: no valid severity values found in ${RAW_CSV}"
  exit 1
fi

echo "Loading dw.dim_severity from: ${RAW_CSV}"
echo "started_at: ${RUN_START_HUMAN}"
echo "Distinct severity levels detected:"
cat "${TMP_VALUES_FILE}" | sed 's/^/  - /'

{
  cat <<'SQL'
CREATE TEMP TABLE stg_severity (
    severity_level integer PRIMARY KEY
);
COPY stg_severity (severity_level) FROM STDIN;
SQL
  cat "${TMP_VALUES_FILE}"
  cat <<'SQL'
\.

-- Insert only missing current rows (Type 2 table, but severity is stable in this dataset)
INSERT INTO dw.dim_severity (
    severity_key,
    severity_level,
    valid_from,
    valid_to,
    is_current
)
SELECT
    s.severity_level AS severity_key,
    s.severity_level AS severity_level,
    NOW() AS valid_from,
    TIMESTAMP '9999-12-31 23:59:59' AS valid_to,
    TRUE AS is_current
FROM stg_severity s
LEFT JOIN dw.dim_severity d
  ON d.severity_level = s.severity_level
 AND d.is_current = TRUE
WHERE d.severity_level IS NULL;

DROP TABLE stg_severity;
SQL
} | docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -v ON_ERROR_STOP=1"

echo "Done. Current dw.dim_severity rows:"
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -c 'SELECT severity_key, severity_level, valid_from, valid_to, is_current FROM dw.dim_severity ORDER BY severity_level, valid_from;'"

RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"
echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
