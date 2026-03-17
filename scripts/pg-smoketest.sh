#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
: "${PG_PORT_HOST:=5432}"

echo "== PostgreSQL smoketest =="
echo "DB=${POSTGRES_DB} USER=${POSTGRES_USER} HOST_PORT=${PG_PORT_HOST}"
echo

fail_count=0

host_psql_test() {
  echo "-- Host psql test"
  if ! command -v psql >/dev/null 2>&1; then
    echo "SKIP: host psql not installed."
    return 0
  fi

  export PGPASSWORD="${POSTGRES_PASSWORD}"

  if psql \
    -h 127.0.0.1 \
    -p "${PG_PORT_HOST}" \
    -U "${POSTGRES_USER}" \
    -d "${POSTGRES_DB}" \
    -v ON_ERROR_STOP=1 \
    -c "SELECT 1 AS ready;
    SELECT to_regnamespace('dw') IS NOT NULL AS has_dw_schema;" >/dev/null; then
    echo "OK: host psql connected and SELECT succeeded."
  else
    echo "ERROR: host psql failed."
    return 1
  fi
}

docker_exec_test() {
  echo "-- docker compose exec test"

  if docker compose \
    --env-file "${ENV_FILE}" \
    -f "${COMPOSE_FILE}" \
    exec -T postgres \
    bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -v ON_ERROR_STOP=1 -c \"SELECT 1 AS ready; SELECT to_regnamespace('dw') IS NOT NULL AS has_dw_schema;\"" \
    >/dev/null; then
    echo "OK: docker exec psql connected and SELECT succeeded."
  else
    echo "ERROR: docker exec psql failed."
    return 1
  fi
}

if ! host_psql_test; then
  fail_count=$((fail_count + 1))
fi
echo

if ! docker_exec_test; then
  fail_count=$((fail_count + 1))
fi
echo

if [[ "${fail_count}" -eq 0 ]]; then
  echo "RESULT: OK"
  exit 0
else
  echo "RESULT: ERROR (${fail_count} failure(s))"
  exit 1
fi
