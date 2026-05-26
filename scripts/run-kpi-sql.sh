#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/infra/compose/compose.yml"
ENV_FILE="${ROOT_DIR}/infra/compose/.env"
SQL_DIR="${ROOT_DIR}/naloga6/sql"

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

if [[ "$#" -gt 0 ]]; then
  sql_files=()
  for sql_file in "$@"; do
    if [[ "${sql_file}" = /* ]]; then
      sql_files+=("${sql_file}")
    else
      sql_files+=("${ROOT_DIR}/${sql_file}")
    fi
  done
else
  mapfile -t sql_files < <(find "${SQL_DIR}" -maxdepth 1 -type f -name '*.sql' | sort)
fi

if [[ "${#sql_files[@]}" -eq 0 ]]; then
  echo "ERROR: no SQL files found."
  exit 1
fi

echo "== KPI SQL validation =="
echo "SQL files: ${#sql_files[@]}"
echo

for sql_file in "${sql_files[@]}"; do
  if [[ ! -f "${sql_file}" ]]; then
    echo "ERROR: SQL file not found: ${sql_file}"
    exit 1
  fi

  rel_path="${sql_file#${ROOT_DIR}/}"
  echo "== ${rel_path} =="
  start_epoch="$(date +%s)"

  docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
    bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -v ON_ERROR_STOP=1 -P pager=off" \
    < "${sql_file}"

  end_epoch="$(date +%s)"
  echo "-- completed in $((end_epoch - start_epoch))s"
  echo
done

echo "RESULT: OK"
