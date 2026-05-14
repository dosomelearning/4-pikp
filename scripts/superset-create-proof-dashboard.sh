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

PROOF_DATASET_NAME="${PROOF_DATASET_NAME:-dw_dim_time_preview}"
PROOF_CHART_NAME="${PROOF_CHART_NAME:-DW Dim Time Preview Chart}"
PROOF_DASHBOARD_TITLE="${PROOF_DASHBOARD_TITLE:-DW Superset Proof Dashboard}"
PROOF_SQL="${PROOF_SQL:-SELECT date_value, year_num, month_num, day_num FROM dw.dim_time}"
PROOF_SCHEMA="${PROOF_SCHEMA:-dw}"
PROOF_DESCRIPTION="${PROOF_DESCRIPTION:-Minimal code-created dashboard proving Superset can read the warehouse.}"
SUPERSET_DEV_USERNAME="${SUPERSET_DEV_USERNAME:-${SUPERSET_ADMIN_USERNAME:-admin}}"
SUPERSET_HOST_BASE_URL="${SUPERSET_HOST_BASE_URL:-http://localhost:${SUPERSET_WEB_PORT_HOST:-18088}}"

docker compose --profile tools --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T superset \
  env \
    PROOF_DATASET_NAME="${PROOF_DATASET_NAME}" \
    PROOF_CHART_NAME="${PROOF_CHART_NAME}" \
    PROOF_DASHBOARD_TITLE="${PROOF_DASHBOARD_TITLE}" \
    PROOF_SQL="${PROOF_SQL}" \
    PROOF_SCHEMA="${PROOF_SCHEMA}" \
    PROOF_DESCRIPTION="${PROOF_DESCRIPTION}" \
    SUPERSET_DEV_USERNAME="${SUPERSET_DEV_USERNAME}" \
    SUPERSET_HOST_BASE_URL="${SUPERSET_HOST_BASE_URL}" \
  python - <<'PY'
import json
import os

from flask import g
from superset.app import create_app

app = create_app()
app.config["MCP_DEV_USERNAME"] = os.environ["SUPERSET_DEV_USERNAME"]

with app.app_context():
    from superset import db
    from superset.commands.chart.create import CreateChartCommand
    from superset.commands.dataset.create import CreateDatasetCommand
    from superset.connectors.sqla.models import SqlaTable
    from superset.extensions import security_manager
    from superset.mcp_service.chart.chart_utils import map_config_to_form_data
    from superset.mcp_service.chart.schemas import parse_chart_config
    from superset.mcp_service.chart.tool.generate_chart import _compile_chart
    from superset.mcp_service.dashboard.tool.generate_dashboard import (
        _create_dashboard_layout,
    )
    from superset.mcp_service.utils.url_utils import get_superset_base_url
    from superset.models.core import Database
    from superset.models.dashboard import Dashboard
    from superset.models.slice import Slice

    dataset_name = os.environ["PROOF_DATASET_NAME"]
    chart_name = os.environ["PROOF_CHART_NAME"]
    dashboard_title = os.environ["PROOF_DASHBOARD_TITLE"]
    dataset_sql = os.environ["PROOF_SQL"]
    schema_name = os.environ["PROOF_SCHEMA"]
    description = os.environ["PROOF_DESCRIPTION"]
    username = os.environ["SUPERSET_DEV_USERNAME"]

    database = db.session.query(Database).filter_by(database_name="dw").one_or_none()
    if database is None:
        raise RuntimeError("Superset database 'dw' is not registered. Run ./scripts/superset-register-dw.sh first.")

    user = db.session.query(security_manager.user_model).filter_by(username=username).one_or_none()
    if user is None:
        raise RuntimeError(f"Superset user '{username}' not found.")
    g.user = user

    dataset = (
        db.session.query(SqlaTable)
        .filter_by(database_id=database.id, table_name=dataset_name)
        .one_or_none()
    )

    if dataset is None:
        dataset = CreateDatasetCommand(
            {
                "database": database.id,
                "table_name": dataset_name,
                "sql": dataset_sql,
                "schema": schema_name,
                "description": description,
            }
        ).run()
    else:
        dataset.sql = dataset_sql
        dataset.schema = schema_name
        dataset.description = description
        if user not in dataset.owners:
            dataset.owners.append(user)
        db.session.commit()

    chart_config = {
        "chart_type": "table",
        "columns": [
            {"name": "date_value", "label": "Date"},
            {"name": "year_num", "label": "Year"},
            {"name": "month_num", "label": "Month"},
            {"name": "day_num", "label": "Day"},
        ],
    }
    parsed_chart_config = parse_chart_config(chart_config)
    form_data = map_config_to_form_data(parsed_chart_config, dataset_id=dataset.id)
    compile_result = _compile_chart(form_data, dataset.id)
    if not compile_result.success:
        raise RuntimeError(f"Proof chart compile failed: {compile_result.error}")

    chart = (
        db.session.query(Slice)
        .filter_by(slice_name=chart_name, datasource_id=dataset.id, datasource_type="table")
        .one_or_none()
    )

    if chart is None:
        chart = CreateChartCommand(
            {
                "slice_name": chart_name,
                "viz_type": form_data["viz_type"],
                "datasource_id": dataset.id,
                "datasource_type": "table",
                "params": json.dumps(form_data),
            }
        ).run()
    else:
        chart.viz_type = form_data["viz_type"]
        chart.params = json.dumps(form_data)
        chart.datasource_name = dataset.datasource_name
        chart.owners = [user]
        db.session.commit()

    dashboard = db.session.query(Dashboard).filter_by(dashboard_title=dashboard_title).one_or_none()
    layout = _create_dashboard_layout([chart])
    json_metadata = json.dumps(
        {
            "filter_scopes": {},
            "expanded_slices": {},
            "refresh_frequency": 0,
            "timed_refresh_immune_slices": [],
            "color_scheme": None,
            "label_colors": {},
            "shared_label_colors": {},
            "color_scheme_domain": [],
            "cross_filters_enabled": False,
            "native_filter_configuration": [],
            "global_chart_configuration": {
                "scope": {
                    "rootPath": ["ROOT_ID"],
                    "excluded": [],
                }
            },
            "chart_configuration": {},
        }
    )

    if dashboard is None:
        dashboard = Dashboard()
        dashboard.dashboard_title = dashboard_title
        dashboard.description = description
        dashboard.json_metadata = json_metadata
        dashboard.position_json = json.dumps(layout)
        dashboard.published = True
        dashboard.owners = [user]
        dashboard.slices = [chart]
        db.session.add(dashboard)
        db.session.commit()
    else:
        dashboard.description = description
        dashboard.json_metadata = json_metadata
        dashboard.position_json = json.dumps(layout)
        dashboard.published = True
        dashboard.owners = [user]
        dashboard.slices = [chart]
        db.session.commit()

    host_base_url = os.environ["SUPERSET_HOST_BASE_URL"].rstrip("/")
    dashboard_url = f"{host_base_url}/superset/dashboard/{dashboard.slug or dashboard.id}/"
    chart_url = f"{host_base_url}/explore/?slice_id={chart.id}"
    dataset_url = f"{host_base_url}/explore/?datasource_type=table&datasource_id={dataset.id}"

    print(json.dumps(
        {
            "dataset_id": dataset.id,
            "dataset_name": dataset.table_name,
            "dataset_url": dataset_url,
            "chart_id": chart.id,
            "chart_name": chart.slice_name,
            "chart_url": chart_url,
            "dashboard_id": dashboard.id,
            "dashboard_title": dashboard.dashboard_title,
            "dashboard_url": dashboard_url,
        },
        indent=2,
    ))
PY
