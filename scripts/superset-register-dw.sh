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

: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
: "${POSTGRES_DB:?POSTGRES_DB is required}"

SUPERSET_DATABASE_NAME="${SUPERSET_DATABASE_NAME:-dw}"
SUPERSET_DW_URI="${SUPERSET_DW_URI:-postgresql+psycopg2://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}}"

docker compose --profile tools --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T superset \
  superset set-database-uri \
  --database_name "${SUPERSET_DATABASE_NAME}" \
  --uri "${SUPERSET_DW_URI}"

docker compose --profile tools --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T superset \
  env SUPERSET_DATABASE_NAME="${SUPERSET_DATABASE_NAME}" SUPERSET_DW_URI="${SUPERSET_DW_URI}" \
  python - <<'PY'
import os
import sys

from superset.app import create_app

database_name = os.environ.get("SUPERSET_DATABASE_NAME", "dw")
expected_uri = os.environ["SUPERSET_DW_URI"]

app = create_app()
with app.app_context():
    from superset.extensions import db
    from superset.models.core import Database

    database = db.session.query(Database).filter_by(database_name=database_name).one_or_none()
    if database is None:
        print(f"ERROR: Superset database '{database_name}' was not created.")
        sys.exit(1)

    database.expose_in_sqllab = True
    database.allow_run_async = False
    database.allow_ctas = False
    database.allow_cvas = False
    database.allow_dml = False
    db.session.commit()

    actual_uri = database.sqlalchemy_uri_decrypted
    if actual_uri != expected_uri:
        print(f"ERROR: Superset database '{database_name}' URI mismatch.")
        sys.exit(1)

    print(f"Registered Superset database '{database_name}' with SQL Lab access enabled.")
PY
