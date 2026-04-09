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

echo "Checking v2 ETL integrity"
echo "started_at: ${RUN_START_HUMAN}"

{
  # Single result-set report:
  # - dimension row counts and duplicate-current checks
  # - v2 fact row counts and FK completeness checks
  # - v1-v2 parity deltas for both fact tables
  cat <<'SQL'
SELECT 'dim_county_current_rows' AS check_name, COUNT(*)::bigint AS check_value
FROM dw.dim_county
WHERE is_current = TRUE
UNION ALL
SELECT 'dim_county_dup_current_nk', COUNT(*)::bigint
FROM (
  SELECT county_nk
  FROM dw.dim_county
  WHERE is_current = TRUE
  GROUP BY county_nk
  HAVING COUNT(*) > 1
) t
UNION ALL
SELECT 'dim_county_dup_current_code', COUNT(*)::bigint
FROM (
  SELECT country_code, state_code, source_county_code
  FROM dw.dim_county
  WHERE is_current = TRUE
    AND source_county_code IS NOT NULL
  GROUP BY country_code, state_code, source_county_code
  HAVING COUNT(*) > 1
) t
UNION ALL
SELECT 'dim_streetcity_current_rows', COUNT(*)::bigint
FROM dw.dim_streetcity
WHERE is_current = TRUE
UNION ALL
SELECT 'dim_streetcity_dup_current_nk', COUNT(*)::bigint
FROM (
  SELECT streetcity_nk
  FROM dw.dim_streetcity
  WHERE is_current = TRUE
  GROUP BY streetcity_nk
  HAVING COUNT(*) > 1
) t
UNION ALL
SELECT 'dim_streetcity_missing_county_fk', COUNT(*)::bigint
FROM dw.dim_streetcity ds
LEFT JOIN dw.dim_county dc
  ON dc.county_key = ds.county_key
WHERE ds.is_current = TRUE
  AND dc.county_key IS NULL
UNION ALL
SELECT 'fact_accident_v2_rows', COUNT(*)::bigint
FROM dw.fact_accident_v2
UNION ALL
SELECT 'fact_accident_v2_missing_streetcity_fk', COUNT(*)::bigint
FROM dw.fact_accident_v2 f
LEFT JOIN dw.dim_streetcity ds
  ON ds.streetcity_key = f.streetcity_key
WHERE ds.streetcity_key IS NULL
UNION ALL
SELECT 'fact_accident_v2_missing_county_fk', COUNT(*)::bigint
FROM dw.fact_accident_v2 f
LEFT JOIN dw.dim_county dc
  ON dc.county_key = f.county_key
WHERE dc.county_key IS NULL
UNION ALL
SELECT 'fact_air_quality_daily_v2_rows', COUNT(*)::bigint
FROM dw.fact_air_quality_daily_v2
UNION ALL
SELECT 'fact_air_quality_daily_v2_missing_county_fk', COUNT(*)::bigint
FROM dw.fact_air_quality_daily_v2 f
LEFT JOIN dw.dim_county dc
  ON dc.county_key = f.county_key
WHERE dc.county_key IS NULL
UNION ALL
SELECT 'v1_v2_accident_row_diff', (
  (SELECT COUNT(*) FROM dw.fact_accident) - (SELECT COUNT(*) FROM dw.fact_accident_v2)
)::bigint
UNION ALL
SELECT 'v1_v2_air_row_diff', (
  (SELECT COUNT(*) FROM dw.fact_air_quality_daily) - (SELECT COUNT(*) FROM dw.fact_air_quality_daily_v2)
)::bigint;
SQL
} | docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -v ON_ERROR_STOP=1"

RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"
echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
