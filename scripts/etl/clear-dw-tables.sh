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

echo "Clearing all tables in schema dw (truncate only, no drops)..."
echo "started_at: ${RUN_START_HUMAN}"

docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -v ON_ERROR_STOP=1" <<'SQL'
DO $$
DECLARE
  tbl_list text;
BEGIN
  SELECT string_agg(format('%I.%I', schemaname, tablename), ', ')
    INTO tbl_list
  FROM pg_tables
  WHERE schemaname = 'dw';

  IF tbl_list IS NULL THEN
    RAISE NOTICE 'No tables found in schema dw.';
  ELSE
    EXECUTE 'TRUNCATE TABLE ' || tbl_list || ' RESTART IDENTITY CASCADE';
    RAISE NOTICE 'Truncated tables: %', tbl_list;
  END IF;
END $$;
SQL

echo "Post-truncate row counts:"
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -c \"
    SELECT table_name, row_count
    FROM (
      SELECT 'dim_time'::text AS table_name, COUNT(*)::bigint AS row_count FROM dw.dim_time
      UNION ALL SELECT 'dim_severity', COUNT(*) FROM dw.dim_severity
      UNION ALL SELECT 'dim_weather_condition', COUNT(*) FROM dw.dim_weather_condition
      UNION ALL SELECT 'dim_road_condition', COUNT(*) FROM dw.dim_road_condition
      UNION ALL SELECT 'dim_location', COUNT(*) FROM dw.dim_location
      UNION ALL SELECT 'fact_accident', COUNT(*) FROM dw.fact_accident
      UNION ALL SELECT 'dim_aqi_category', COUNT(*) FROM dw.dim_aqi_category
      UNION ALL SELECT 'dim_defining_parameter', COUNT(*) FROM dw.dim_defining_parameter
      UNION ALL SELECT 'fact_air_quality_daily', COUNT(*) FROM dw.fact_air_quality_daily
    ) t
    ORDER BY table_name;
  \""

RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"
echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
