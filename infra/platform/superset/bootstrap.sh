#!/usr/bin/env bash
set -euo pipefail

export SUPERSET_CONFIG_PATH="${SUPERSET_CONFIG_PATH:-/app/pythonpath/superset_config.py}"
export SUPERSET_HOME="${SUPERSET_HOME:-/app/superset_home}"

mkdir -p "${SUPERSET_HOME}"

superset db upgrade

python <<'PY'
import os

from superset.app import create_app

app = create_app()

with app.app_context():
    sm = app.appbuilder.sm
    username = os.environ["SUPERSET_ADMIN_USERNAME"]
    user = sm.find_user(username=username)
    if user is None:
        sm.add_user(
            username=username,
            first_name=os.environ.get("SUPERSET_ADMIN_FIRST_NAME", "Project"),
            last_name=os.environ.get("SUPERSET_ADMIN_LAST_NAME", "Admin"),
            email=os.environ.get("SUPERSET_ADMIN_EMAIL", "admin@example.com"),
            role=sm.find_role("Admin"),
            password=os.environ["SUPERSET_ADMIN_PASSWORD"],
        )
        print(f"Created Superset admin user: {username}")
    else:
        print(f"Superset admin user already exists: {username}")
PY

superset init

exec gunicorn \
  --bind 0.0.0.0:8088 \
  --workers "${SUPERSET_GUNICORN_WORKERS:-2}" \
  --worker-class gthread \
  --threads "${SUPERSET_GUNICORN_THREADS:-20}" \
  --timeout 120 \
  --limit-request-line 0 \
  --limit-request-field_size 0 \
  "superset.app:create_app()"
