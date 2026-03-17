#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/infra/compose/compose.yml"
ENV_FILE="${ROOT_DIR}/infra/compose/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: env file not found: ${ENV_FILE}"
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

START_TS="${1:-2016-01-01 00:00:00}"
END_TS="${2:-2026-12-31 23:00:00}"

if [[ "${START_TS}" > "${END_TS}" ]]; then
  echo "ERROR: START_TS must be <= END_TS"
  echo "  START_TS: ${START_TS}"
  echo "  END_TS:   ${END_TS}"
  exit 1
fi

echo "Populating dw.dim_time via generate_series..."
echo "  started_at: ${RUN_START_HUMAN}"
echo "  start: ${START_TS}"
echo "  end:   ${END_TS}"

docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -v ON_ERROR_STOP=1" <<SQL
INSERT INTO dw.dim_time (
  time_key,
  date_value,
  year_num,
  month_num,
  day_num,
  hour_num,
  day_of_week_num,
  day_of_week_name,
  is_weekend
)
SELECT
  TO_CHAR(g.ts, 'YYYYMMDDHH24')::bigint AS time_key,
  g.ts::date AS date_value,
  EXTRACT(YEAR FROM g.ts)::int AS year_num,
  EXTRACT(MONTH FROM g.ts)::int AS month_num,
  EXTRACT(DAY FROM g.ts)::int AS day_num,
  EXTRACT(HOUR FROM g.ts)::int AS hour_num,
  EXTRACT(DOW FROM g.ts)::int AS day_of_week_num,
  TO_CHAR(g.ts, 'FMDay') AS day_of_week_name,
  (EXTRACT(DOW FROM g.ts) IN (0, 6)) AS is_weekend
FROM generate_series(
  '${START_TS}'::timestamp,
  '${END_TS}'::timestamp,
  interval '1 hour'
) AS g(ts)
ON CONFLICT (time_key) DO NOTHING;
SQL

echo "Done. Current dw.dim_time row count:"
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -At -c \"SELECT count(*) FROM dw.dim_time;\""

RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"
echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
