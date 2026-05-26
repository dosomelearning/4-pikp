#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/infra/compose/compose.yml"
ENV_FILE="${ROOT_DIR}/infra/compose/.env"
SQL_DIR="${ROOT_DIR}/naloga6/sql"
CONTAINER_SQL_DIR="/tmp/pikp_kpi_sql"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: env file not found: ${ENV_FILE}"
  exit 1
fi

if [[ ! -d "${SQL_DIR}" ]]; then
  echo "ERROR: SQL directory not found: ${SQL_DIR}"
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a

SUPERSET_DEV_USERNAME="${SUPERSET_DEV_USERNAME:-${SUPERSET_ADMIN_USERNAME:-admin}}"
SUPERSET_HOST_BASE_URL="${SUPERSET_HOST_BASE_URL:-http://localhost:${SUPERSET_WEB_PORT_HOST:-18088}}"

superset_container_id="$(
  docker compose --profile tools --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" ps -q superset
)"

if [[ -z "${superset_container_id}" ]]; then
  echo "ERROR: Superset container is not running. Run ./scripts/superset-up.sh first."
  exit 1
fi

docker compose --profile tools --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T superset \
  mkdir -p "${CONTAINER_SQL_DIR}"

docker cp "${SQL_DIR}/." "${superset_container_id}:${CONTAINER_SQL_DIR}/"

docker compose --profile tools --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T superset \
  env \
    CONTAINER_SQL_DIR="${CONTAINER_SQL_DIR}" \
    SUPERSET_DEV_USERNAME="${SUPERSET_DEV_USERNAME}" \
    SUPERSET_HOST_BASE_URL="${SUPERSET_HOST_BASE_URL}" \
  python - <<'PY'
import json
import os
import re
from pathlib import Path

from flask import g
from sqlalchemy import text
from superset.app import create_app


SQL_DIR = Path(os.environ["CONTAINER_SQL_DIR"])
USERNAME = os.environ["SUPERSET_DEV_USERNAME"]
HOST_BASE_URL = os.environ["SUPERSET_HOST_BASE_URL"].rstrip("/")
DATASET_PREFIX = "kpi_"
TABLE_CHART_PREFIX = "KPI SQL Preview - "
GRAPH_CHART_PREFIX = "KPI - "


def clean_sql(sql: str) -> str:
    return sql.strip().rstrip(";").strip()


def dataset_name(sql_path: Path) -> str:
    stem = sql_path.stem
    return DATASET_PREFIX + re.sub(r"^\d+_", "", stem)


def table_chart_name(sql_path: Path) -> str:
    return TABLE_CHART_PREFIX + sql_path.stem


def col(name, aggregate=None, label=None):
    value = {"name": name}
    if aggregate:
        value["aggregate"] = aggregate
    if label:
        value["label"] = label
    return value


def sql_metric(label, sql_expression):
    return {
        "expressionType": "SQL",
        "sqlExpression": sql_expression,
        "label": label,
        "optionName": f"metric_{label}",
        "hasCustomLabel": True,
    }


GRAPH_CHARTS = [
    {
        "name": "KPI1 Accident Count",
        "dataset": "kpi_kpi_accident_count_period",
        "config": {
            "chart_type": "big_number",
            "metric": col("accident_count", "SUM"),
            "temporal_column": "accident_date",
            "time_grain": "P1M",
            "show_trendline": True,
            "compare_lag": 1,
            "subheader": "Monthly accidents. Higher is unfavorable.",
            "y_axis_format": ",.0f",
        },
    },
    {
        "name": "KPI1 Accident Count Trend",
        "dataset": "kpi_kpi_accident_count_period",
        "config": {
            "chart_type": "xy",
            "kind": "line",
            "x": col("accident_date"),
            "y": [col("accident_count", "SUM")],
            "time_grain": "P1M",
            "row_limit": 5000,
            "x_axis": {"title": "Month"},
            "y_axis": {"title": "Accidents", "format": ",.0f"},
        },
    },
    {
        "name": "KPI1 Accidents by Weekday and Hour",
        "dataset": "kpi_kpi_accident_count_hour_dow",
        "config": {
            "chart_type": "xy",
            "kind": "bar",
            "x": col("hour_num"),
            "y": [col("accident_count", "SUM")],
            "group_by": [col("day_of_week_name")],
            "row_limit": 5000,
            "x_axis": {"title": "Hour of day"},
            "y_axis": {"title": "Accidents", "format": ",.0f"},
            "legend": {"show": True, "position": "right"},
        },
    },
    {
        "name": "KPI1 Accidents by Severity Over Time",
        "dataset": "kpi_kpi_accident_count_severity_time",
        "emit_filter": True,
        "config": {
            "chart_type": "xy",
            "kind": "bar",
            "x": col("accident_date"),
            "y": [col("accident_count", "SUM")],
            "group_by": [col("severity_level")],
            "stacked": True,
            "time_grain": "P1M",
            "row_limit": 5000,
            "x_axis": {"title": "Month"},
            "y_axis": {"title": "Accidents", "format": ",.0f"},
        },
    },
    {
        "name": "KPI1 Top Counties by Accident Count",
        "dataset": "kpi_kpi_accident_count_county",
        "emit_filter": True,
        "config": {
            "chart_type": "xy",
            "kind": "bar",
            "orientation": "horizontal",
            "x": col("county_name"),
            "y": [col("accident_count", "SUM")],
            "group_by": [col("state_code")],
            "row_limit": 100,
            "x_axis": {"title": "County"},
            "y_axis": {"title": "Accidents", "format": ",.0f"},
        },
    },
    {
        "name": "KPI2 Median Accident Duration",
        "dataset": "kpi_kpi_accident_duration_period",
        "metric_override": sql_metric(
            "median_duration_minutes",
            "PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY accident_duration_minutes)",
        ),
        "config": {
            "chart_type": "big_number",
            "metric": col("accident_duration_minutes", "AVG"),
            "temporal_column": "accident_date",
            "time_grain": "P1M",
            "show_trendline": True,
            "compare_lag": 1,
            "subheader": "Median minutes. Higher is unfavorable.",
            "y_axis_format": ",.2f",
        },
    },
    {
        "name": "KPI2 Duration Trend",
        "dataset": "kpi_kpi_accident_duration_period",
        "metrics_override": [
            sql_metric(
                "median_duration_minutes",
                "PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY accident_duration_minutes)",
            ),
            sql_metric(
                "p90_duration_minutes",
                "PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY accident_duration_minutes)",
            ),
        ],
        "config": {
            "chart_type": "xy",
            "kind": "line",
            "x": col("accident_date"),
            "y": [col("accident_duration_minutes", "AVG")],
            "time_grain": "P1M",
            "row_limit": 5000,
            "x_axis": {"title": "Month"},
            "y_axis": {"title": "Duration minutes", "format": ",.2f"},
        },
    },
    {
        "name": "KPI2 Duration by Weather",
        "dataset": "kpi_kpi_accident_duration_weather",
        "emit_filter": True,
        "metrics_override": [
            sql_metric(
                "median_duration_minutes",
                "PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY accident_duration_minutes)",
            )
        ],
        "config": {
            "chart_type": "xy",
            "kind": "bar",
            "orientation": "horizontal",
            "x": col("weather_condition_name"),
            "y": [col("accident_duration_minutes", "AVG")],
            "row_limit": 15,
            "x_axis": {"title": "Weather condition"},
            "y_axis": {"title": "Median duration minutes", "format": ",.2f"},
        },
    },
    {
        "name": "KPI2 Duration by Severity and Road Signal",
        "dataset": "kpi_kpi_accident_duration_severity_road",
        "emit_filter": True,
        "metrics_override": [
            sql_metric(
                "median_duration_minutes",
                "PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY accident_duration_minutes)",
            )
        ],
        "config": {
            "chart_type": "xy",
            "kind": "bar",
            "x": col("primary_road_signal"),
            "y": [col("accident_duration_minutes", "AVG")],
            "group_by": [col("severity_level")],
            "row_limit": 100,
            "x_axis": {"title": "Primary road signal"},
            "y_axis": {"title": "Median duration minutes", "format": ",.2f"},
            "legend": {"show": True, "position": "right"},
        },
    },
    {
        "name": "KPI2 Top Counties by Accident Count",
        "dataset": "kpi_kpi_accident_count_duration_county",
        "emit_filter": True,
        "config": {
            "chart_type": "xy",
            "kind": "bar",
            "orientation": "horizontal",
            "x": col("county_name"),
            "y": [col("accident_count", "SUM")],
            "group_by": [col("state_code")],
            "row_limit": 30,
            "x_axis": {"title": "County"},
            "y_axis": {"title": "Accidents", "format": ",.0f"},
            "legend": {"show": True, "position": "right"},
        },
    },
    {
        "name": "KPI3 Bad-Air AQI Share",
        "dataset": "kpi_kpi_aqi_bad_air_period",
        "metric_override": sql_metric(
            "bad_air_pct",
            "100.0 * SUM(bad_air_observation_count)::numeric / NULLIF(SUM(aqi_observation_count), 0)",
        ),
        "config": {
            "chart_type": "big_number",
            "metric": col("bad_air_pct", "AVG"),
            "temporal_column": "observation_date",
            "time_grain": "P1M",
            "show_trendline": True,
            "compare_lag": 1,
            "subheader": "AQI > 100 share. Higher is unfavorable.",
            "y_axis_format": ",.2f",
        },
    },
    {
        "name": "KPI3 Bad-Air Share Trend",
        "dataset": "kpi_kpi_aqi_bad_air_period",
        "metrics_override": [
            sql_metric(
                "bad_air_pct",
                "100.0 * SUM(bad_air_observation_count)::numeric / NULLIF(SUM(aqi_observation_count), 0)",
            ),
            sql_metric(
                "avg_aqi",
                "SUM(aqi_sum)::numeric / NULLIF(SUM(aqi_observation_count), 0)",
            ),
        ],
        "config": {
            "chart_type": "xy",
            "kind": "line",
            "x": col("observation_date"),
            "y": [col("bad_air_pct", "AVG"), col("avg_aqi", "AVG")],
            "time_grain": "P1M",
            "row_limit": 5000,
            "x_axis": {"title": "Month"},
            "y_axis": {"title": "Bad-air percent / AQI", "format": ",.2f"},
        },
    },
    {
        "name": "KPI3 Counties by Bad-Air Share",
        "dataset": "kpi_kpi_aqi_bad_air_county",
        "metrics_override": [
            sql_metric(
                "bad_air_pct",
                "100.0 * SUM(bad_air_observation_count)::numeric / NULLIF(SUM(aqi_observation_count), 0)",
            )
        ],
        "emit_filter": True,
        "config": {
            "chart_type": "xy",
            "kind": "bar",
            "orientation": "horizontal",
            "x": col("county_name"),
            "y": [col("bad_air_pct", "AVG")],
            "group_by": [col("state_code")],
            "row_limit": 100,
            "x_axis": {"title": "County"},
            "y_axis": {"title": "Bad-air percent", "format": ",.2f"},
        },
    },
    {
        "name": "KPI3 Bad-Air by Defining Parameter",
        "dataset": "kpi_kpi_aqi_bad_air_parameter",
        "emit_filter": True,
        "config": {
            "chart_type": "pie",
            "dimension": col("defining_parameter_name"),
            "metric": col("bad_air_observation_count", "SUM"),
            "donut": True,
            "show_labels": True,
            "label_type": "key_value_percent",
            "row_limit": 20,
            "show_total": True,
        },
    },
    {
        "name": "Combined Accidents and AQI by Month",
        "dataset": "kpi_kpi_accidents_vs_aqi_monthly",
        "config": {
            "chart_type": "mixed_timeseries",
            "x": col("metric_month"),
            "time_grain": "P1M",
            "y": [col("accident_count", "SUM")],
            "primary_kind": "bar",
            "y_secondary": [col("bad_air_pct", "AVG")],
            "secondary_kind": "line",
            "row_limit": 5000,
            "x_axis": {"title": "Month"},
            "y_axis": {"title": "Accidents", "format": ",.0f"},
            "y_axis_secondary": {"title": "Bad-air percent", "format": ",.2f"},
        },
    },
    {
        "name": "AQI Accident Count Correlation",
        "dataset": "kpi_kpi_accidents_aqi_state_month_correlation_base",
        "metric_override": sql_metric(
            "corr_accident_count_bad_air_pct",
            "CORR(accident_count::numeric, bad_air_pct::numeric)",
        ),
        "config": {
            "chart_type": "big_number",
            "metric": col("accident_count", "SUM"),
            "show_trendline": False,
            "subheader": "Correlation: accident count vs bad-air share",
            "y_axis_format": ",.4f",
        },
    },
    {
        "name": "AQI Duration Correlation",
        "dataset": "kpi_kpi_accidents_aqi_state_month_correlation_base",
        "metric_override": sql_metric(
            "corr_avg_duration_bad_air_pct",
            "CORR(avg_duration_minutes::numeric, bad_air_pct::numeric)",
        ),
        "config": {
            "chart_type": "big_number",
            "metric": col("avg_duration_minutes", "AVG"),
            "show_trendline": False,
            "subheader": "Correlation: average duration vs bad-air share",
            "y_axis_format": ",.4f",
        },
    },
    {
        "name": "AQI Severity Correlation",
        "dataset": "kpi_kpi_accidents_aqi_state_month_correlation_base",
        "metric_override": sql_metric(
            "corr_severe_accident_pct_bad_air_pct",
            "CORR(severe_accident_pct::numeric, bad_air_pct::numeric)",
        ),
        "config": {
            "chart_type": "big_number",
            "metric": col("severe_accident_pct", "AVG"),
            "show_trendline": False,
            "subheader": "Correlation: severe accident share vs bad-air share",
            "y_axis_format": ",.4f",
        },
    },
    {
        "name": "AQI vs Accident Count Scatter",
        "dataset": "kpi_kpi_accidents_aqi_state_month_correlation_base",
        "emit_filter": True,
        "config": {
            "chart_type": "xy",
            "kind": "scatter",
            "x": col("bad_air_pct"),
            "y": [col("accident_count", "SUM")],
            "group_by": [col("state_code")],
            "row_limit": 5000,
            "x_axis": {"title": "Bad-air percent", "format": ",.2f"},
            "y_axis": {"title": "Accident count", "format": ",.0f"},
            "legend": {"show": True, "position": "right"},
        },
    },
    {
        "name": "AQI vs Duration Scatter",
        "dataset": "kpi_kpi_accidents_aqi_state_month_correlation_base",
        "emit_filter": True,
        "config": {
            "chart_type": "xy",
            "kind": "scatter",
            "x": col("bad_air_pct"),
            "y": [col("avg_duration_minutes", "AVG")],
            "group_by": [col("state_code")],
            "row_limit": 5000,
            "x_axis": {"title": "Bad-air percent", "format": ",.2f"},
            "y_axis": {"title": "Average duration minutes", "format": ",.2f"},
            "legend": {"show": True, "position": "right"},
        },
    },
    {
        "name": "State AQI Accident Correlation Ranking",
        "dataset": "kpi_kpi_accidents_aqi_state_month_correlation_base",
        "metrics_override": [
            sql_metric(
                "corr_accident_count_bad_air_pct",
                "CORR(accident_count::numeric, bad_air_pct::numeric)",
            )
        ],
        "emit_filter": True,
        "config": {
            "chart_type": "xy",
            "kind": "bar",
            "orientation": "horizontal",
            "x": col("state_code"),
            "y": [col("accident_count", "SUM")],
            "row_limit": 60,
            "x_axis": {"title": "State"},
            "y_axis": {"title": "Correlation", "format": ",.4f"},
        },
    },
    {
        "name": "Accidents and AQI Monthly Comparison",
        "dataset": "kpi_kpi_accidents_aqi_state_month_correlation_base",
        "emit_filter": True,
        "config": {
            "chart_type": "mixed_timeseries",
            "x": col("metric_month"),
            "time_grain": "P1M",
            "y": [col("accident_count", "SUM")],
            "primary_kind": "bar",
            "y_secondary": [col("bad_air_pct", "AVG")],
            "secondary_kind": "line",
            "row_limit": 5000,
            "x_axis": {"title": "Month"},
            "y_axis": {"title": "Accidents", "format": ",.0f"},
            "y_axis_secondary": {"title": "Bad-air percent", "format": ",.2f"},
        },
    },
]


app = create_app()
app.config["MCP_DEV_USERNAME"] = USERNAME

with app.app_context():
    from superset import db
    from superset.commands.chart.create import CreateChartCommand
    from superset.commands.dataset.create import CreateDatasetCommand
    from superset.connectors.sqla.models import SqlaTable
    from superset.extensions import security_manager
    from superset.mcp_service.chart.chart_utils import map_config_to_form_data
    from superset.mcp_service.chart.schemas import parse_chart_config
    from superset.mcp_service.chart.tool.generate_chart import _compile_chart
    from superset.models.core import Database
    from superset.models.slice import Slice

    database = db.session.query(Database).filter_by(database_name="dw").one_or_none()
    if database is None:
        raise RuntimeError("Superset database 'dw' is not registered. Run ./scripts/superset-register-dw.sh first.")

    user = db.session.query(security_manager.user_model).filter_by(username=USERNAME).one_or_none()
    if user is None:
        raise RuntimeError(f"Superset user '{USERNAME}' not found.")
    g.user = user

    sql_files = sorted(SQL_DIR.glob("*.sql"))
    if not sql_files:
        raise RuntimeError(f"No SQL files found in {SQL_DIR}")

    datasets = {}
    dataset_tests = []
    table_charts = []
    graph_charts = []

    for sql_file in sql_files:
        name = dataset_name(sql_file)
        sql = clean_sql(sql_file.read_text())
        preview_sql = f"SELECT * FROM ({sql}) AS kpi_sql_preview LIMIT 5"

        with database.get_sqla_engine() as engine:
            with engine.connect() as conn:
                result = conn.execute(text(preview_sql))
                columns = list(result.keys())
                rows = result.fetchmany(5)
        dataset_tests.append({"dataset": name, "columns": columns, "preview_rows": len(rows)})

        dataset = (
            db.session.query(SqlaTable)
            .filter_by(database_id=database.id, table_name=name)
            .one_or_none()
        )
        if dataset is None:
            dataset = CreateDatasetCommand(
                {
                    "database": database.id,
                    "table_name": name,
                    "sql": sql,
                    "schema": "dw",
                    "description": f"KPI virtual dataset from {sql_file.name}.",
                }
            ).run()
        else:
            dataset.sql = sql
            dataset.schema = "dw"
            dataset.description = f"KPI virtual dataset from {sql_file.name}."
            if user not in dataset.owners:
                dataset.owners.append(user)
            db.session.commit()
            if hasattr(dataset, "fetch_metadata"):
                dataset.fetch_metadata()
                db.session.commit()

        if name in {
            "kpi_kpi_accident_count_period",
            "kpi_kpi_accident_count_hour_dow",
            "kpi_kpi_accident_count_severity_time",
            "kpi_kpi_accident_count_county",
        }:
            dataset.main_dttm_col = "accident_date"
            db.session.commit()
        if name in {
            "kpi_kpi_accident_duration_period",
            "kpi_kpi_accident_duration_weather",
            "kpi_kpi_accident_duration_severity_road",
            "kpi_kpi_accident_count_duration_county",
        }:
            dataset.main_dttm_col = "accident_date"
            db.session.commit()
        if name in {
            "kpi_kpi_aqi_bad_air_period",
            "kpi_kpi_aqi_bad_air_county",
            "kpi_kpi_aqi_bad_air_parameter",
        }:
            dataset.main_dttm_col = "observation_date"
            db.session.commit()
        if name == "kpi_kpi_accidents_aqi_state_month_correlation_base":
            dataset.main_dttm_col = "metric_month"
            db.session.commit()

        datasets[name] = dataset

        table_config = {
            "chart_type": "table",
            "columns": [{"name": column, "label": column} for column in columns],
            "row_limit": 1000,
        }
        parsed_table_config = parse_chart_config(table_config)
        table_form_data = map_config_to_form_data(parsed_table_config, dataset_id=dataset.id)
        table_compile = _compile_chart(table_form_data, dataset.id)
        if not table_compile.success:
            raise RuntimeError(f"Table chart compile failed for {name}: {table_compile.error}")

        chart_name = table_chart_name(sql_file)
        chart = (
            db.session.query(Slice)
            .filter_by(slice_name=chart_name, datasource_id=dataset.id, datasource_type="table")
            .one_or_none()
        )
        if chart is None:
            chart = CreateChartCommand(
                {
                    "slice_name": chart_name,
                    "viz_type": table_form_data["viz_type"],
                    "datasource_id": dataset.id,
                    "datasource_type": "table",
                    "params": json.dumps(table_form_data),
                }
            ).run()
        else:
            chart.viz_type = table_form_data["viz_type"]
            chart.params = json.dumps(table_form_data)
            chart.datasource_name = dataset.datasource_name
            chart.owners = [user]
            db.session.commit()
        table_charts.append(chart)

    for spec in GRAPH_CHARTS:
        dataset = datasets.get(spec["dataset"])
        if dataset is None:
            raise RuntimeError(f"Missing dataset for graph chart {spec['name']}: {spec['dataset']}")

        parsed_chart_config = parse_chart_config(spec["config"])
        form_data = map_config_to_form_data(parsed_chart_config, dataset_id=dataset.id)
        if spec.get("emit_filter"):
            form_data["emit_filter"] = True
        if "metric_override" in spec:
            form_data["metric"] = spec["metric_override"]
        if "metrics_override" in spec:
            form_data["metrics"] = spec["metrics_override"]
        if "append_metrics" in spec:
            form_data["metrics"] = form_data.get("metrics", []) + spec["append_metrics"]
        if spec["dataset"] in {
            "kpi_kpi_accident_count_period",
            "kpi_kpi_accident_count_hour_dow",
            "kpi_kpi_accident_count_severity_time",
            "kpi_kpi_accident_count_county",
        }:
            form_data["granularity_sqla"] = "accident_date"
        if spec["dataset"] in {
            "kpi_kpi_accident_duration_period",
            "kpi_kpi_accident_duration_weather",
            "kpi_kpi_accident_duration_severity_road",
            "kpi_kpi_accident_count_duration_county",
        }:
            form_data["granularity_sqla"] = "accident_date"
        if spec["dataset"] in {
            "kpi_kpi_aqi_bad_air_period",
            "kpi_kpi_aqi_bad_air_county",
            "kpi_kpi_aqi_bad_air_parameter",
        }:
            form_data["granularity_sqla"] = "observation_date"
        if spec["dataset"] == "kpi_kpi_accidents_aqi_state_month_correlation_base":
            form_data["granularity_sqla"] = "metric_month"
        compile_result = _compile_chart(form_data, dataset.id)
        if not compile_result.success:
            raise RuntimeError(f"Graph chart compile failed for {spec['name']}: {compile_result.error}")

        chart_name = GRAPH_CHART_PREFIX + spec["name"]
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
        graph_charts.append(chart)

    output = {
        "datasets": [
            {
                "id": dataset.id,
                "name": name,
                "url": f"{HOST_BASE_URL}/explore/?datasource_type=table&datasource_id={dataset.id}",
            }
            for name, dataset in sorted(datasets.items())
        ],
        "dataset_tests": dataset_tests,
        "table_preview_charts": [
            {
                "id": chart.id,
                "name": chart.slice_name,
                "url": f"{HOST_BASE_URL}/explore/?slice_id={chart.id}",
            }
            for chart in table_charts
        ],
        "graphical_charts": [
            {
                "id": chart.id,
                "name": chart.slice_name,
                "viz_type": chart.viz_type,
                "url": f"{HOST_BASE_URL}/explore/?slice_id={chart.id}",
            }
            for chart in graph_charts
        ],
    }

    print(json.dumps(output, indent=2))
PY
