#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/infra/compose/compose.yml"
ENV_FILE="${ROOT_DIR}/infra/compose/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: env file not found: ${ENV_FILE}"
  exit 1
fi

dashboard_key="${1:-}"
if [[ -z "${dashboard_key}" ]]; then
  echo "Usage: $0 <kpi1|kpi2|kpi3|kpi4>"
  exit 1
fi

case "${dashboard_key}" in
  kpi1|kpi2|kpi3|kpi4)
    ;;
  *)
    echo "ERROR: unsupported dashboard key: ${dashboard_key}"
    echo "Usage: $0 <kpi1|kpi2|kpi3|kpi4>"
    exit 1
    ;;
esac

# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a

SUPERSET_DEV_USERNAME="${SUPERSET_DEV_USERNAME:-${SUPERSET_ADMIN_USERNAME:-admin}}"
SUPERSET_HOST_BASE_URL="${SUPERSET_HOST_BASE_URL:-http://localhost:${SUPERSET_WEB_PORT_HOST:-18088}}"

docker compose --profile tools --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T superset \
  env \
    DASHBOARD_KEY="${dashboard_key}" \
    SUPERSET_DEV_USERNAME="${SUPERSET_DEV_USERNAME}" \
    SUPERSET_HOST_BASE_URL="${SUPERSET_HOST_BASE_URL}" \
  python - <<'PY'
import json
import os

from flask import g
from superset.app import create_app


DASHBOARD_KEY = os.environ["DASHBOARD_KEY"]
USERNAME = os.environ["SUPERSET_DEV_USERNAME"]
HOST_BASE_URL = os.environ["SUPERSET_HOST_BASE_URL"].rstrip("/")

DASHBOARDS = {
    "kpi1": {
        "title": "KPI 1 - Accident Frequency Dashboard",
        "description": "Accident frequency dashboard: total accidents, monthly trend, weekday/hour pattern, severity trend, and county concentration.",
        "sections": [
            [
                {"name": "KPI - KPI1 Accident Count", "width": 4, "height": 32},
                {"name": "KPI - KPI1 Accident Count Trend", "width": 8, "height": 32},
            ],
            [
                {"name": "KPI - KPI1 Accidents by Weekday and Hour", "width": 12, "height": 48},
            ],
            [
                {"name": "KPI - KPI1 Accidents by Severity Over Time", "width": 6, "height": 44},
                {"name": "KPI - KPI1 Top Counties by Accident Count", "width": 6, "height": 44},
            ],
        ],
    },
    "kpi2": {
        "title": "KPI 2 - Accident Duration Dashboard",
        "description": "Accident handling duration dashboard: median duration, duration trend, weather relationship, road/severity context, and county volume.",
        "sections": [
            [
                {"name": "KPI - KPI2 Median Accident Duration", "width": 4, "height": 32},
                {"name": "KPI - KPI2 Duration Trend", "width": 8, "height": 32},
            ],
            [
                {"name": "KPI - KPI2 Duration by Weather", "width": 6, "height": 44},
                {"name": "KPI - KPI2 Duration by Severity and Road Signal", "width": 6, "height": 44},
            ],
            [
                {"name": "KPI - KPI2 Top Counties by Accident Count", "width": 12, "height": 48},
            ],
        ],
    },
    "kpi3": {
        "title": "KPI 3 - Air Quality Dashboard",
        "description": "Air-quality dashboard: bad-air AQI share, monthly trend, county ranking, and defining-parameter contribution.",
        "sections": [
            [
                {"name": "KPI - KPI3 Bad-Air AQI Share", "width": 4, "height": 32},
                {"name": "KPI - KPI3 Bad-Air Share Trend", "width": 8, "height": 32},
            ],
            [
                {"name": "KPI - KPI3 Counties by Bad-Air Share", "width": 7, "height": 48},
                {"name": "KPI - KPI3 Bad-Air by Defining Parameter", "width": 5, "height": 48},
            ],
        ],
    },
    "kpi4": {
        "title": "Dashboard 4 - Accidents and Air Quality Relationship",
        "description": "Cross-domain relationship dashboard: correlation cards, AQI/accident scatter plots, state correlation ranking, and monthly accident/AQI comparison.",
        "sections": [
            [
                {"name": "KPI - AQI Accident Count Correlation", "width": 4, "height": 28},
                {"name": "KPI - AQI Duration Correlation", "width": 4, "height": 28},
                {"name": "KPI - AQI Severity Correlation", "width": 4, "height": 28},
            ],
            [
                {"name": "KPI - AQI vs Accident Count Scatter", "width": 6, "height": 48},
                {"name": "KPI - AQI vs Duration Scatter", "width": 6, "height": 48},
            ],
            [
                {"name": "KPI - State AQI Accident Correlation Ranking", "width": 5, "height": 48},
                {"name": "KPI - Accidents and AQI Monthly Comparison", "width": 7, "height": 48},
            ],
        ],
    },
}


def chart_component_id(chart_id):
    return f"CHART-{chart_id}"


def row_id(index):
    return f"ROW-KPI-{DASHBOARD_KEY}-{index}"


def column_id(row_index, column_index):
    return f"COLUMN-KPI-{DASHBOARD_KEY}-{row_index}-{column_index}"


def build_layout(section_charts):
    layout = {
        "ROOT_ID": {"children": ["GRID_ID"], "id": "ROOT_ID", "type": "ROOT"},
        "GRID_ID": {"children": [], "id": "GRID_ID", "parents": ["ROOT_ID"], "type": "GRID"},
        "DASHBOARD_VERSION_KEY": "v2",
    }

    for row_index, row_charts in enumerate(section_charts, start=1):
        rid = row_id(row_index)
        layout["GRID_ID"]["children"].append(rid)
        layout[rid] = {
            "children": [],
            "id": rid,
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
            "parents": ["ROOT_ID", "GRID_ID"],
            "type": "ROW",
        }

        for column_index, item in enumerate(row_charts, start=1):
            cid = column_id(row_index, column_index)
            chart = item["chart"]
            chid = chart_component_id(chart.id)
            layout[rid]["children"].append(cid)
            layout[cid] = {
                "children": [chid],
                "id": cid,
                "meta": {
                    "background": "BACKGROUND_TRANSPARENT",
                    "width": item["width"],
                },
                "parents": ["ROOT_ID", "GRID_ID", rid],
                "type": "COLUMN",
            }
            layout[chid] = {
                "children": [],
                "id": chid,
                "meta": {
                    "chartId": chart.id,
                    "height": item["height"],
                    "sliceName": chart.slice_name,
                    "uuid": str(chart.uuid),
                    "width": item["width"],
                },
                "parents": ["ROOT_ID", "GRID_ID", rid, cid],
                "type": "CHART",
            }

    return layout


def excluded_except(all_charts, included_charts):
    included_ids = {chart.id for chart in included_charts}
    return [chart.id for chart in all_charts if chart.id not in included_ids]


def column_targets(datasets, column_name):
    return [
        {
            "column": {"name": column_name},
            "datasetId": dataset_id,
        }
        for dataset_id in datasets
    ]


def select_filter(filter_id, name, targets, excluded, cascade_parent_ids=None):
    return {
        "cascadeParentIds": cascade_parent_ids or [],
        "controlValues": {
            "defaultToFirstItem": False,
            "enableEmptyFilter": False,
            "inverseSelection": False,
            "multiSelect": True,
            "searchAllOptions": True,
        },
        "filterType": "filter_select",
        "id": filter_id,
        "name": name,
        "scope": {
            "rootPath": ["ROOT_ID"],
            "excluded": excluded,
        },
        "targets": targets,
        "type": "NATIVE_FILTER",
    }


def time_filter(filter_id, name, targets, excluded):
    return {
        "cascadeParentIds": [],
        "filterType": "filter_time",
        "id": filter_id,
        "name": name,
        "scope": {
            "rootPath": ["ROOT_ID"],
            "excluded": excluded,
        },
        "targets": targets,
        "type": "NATIVE_FILTER",
    }


def build_json_metadata(all_charts, charts_by_name):
    json_metadata = {
        "filter_scopes": {},
        "expanded_slices": {},
        "refresh_frequency": 0,
        "timed_refresh_immune_slices": [],
        "color_scheme": None,
        "label_colors": {},
        "shared_label_colors": [],
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
        "map_label_colors": {},
    }

    if DASHBOARD_KEY != "kpi1":
        if DASHBOARD_KEY == "kpi2":
            dashboard2_chart_names = [
                "KPI - KPI2 Median Accident Duration",
                "KPI - KPI2 Duration Trend",
                "KPI - KPI2 Duration by Weather",
                "KPI - KPI2 Duration by Severity and Road Signal",
                "KPI - KPI2 Top Counties by Accident Count",
            ]
            filterable_charts = [charts_by_name[name] for name in dashboard2_chart_names]
            filterable_dataset_ids = sorted({chart.datasource_id for chart in filterable_charts})
            state_filter_id = "NATIVE_FILTER-KPI2-STATE"

            json_metadata["cross_filters_enabled"] = True
            json_metadata["native_filter_configuration"] = [
                time_filter(
                    "NATIVE_FILTER-KPI2-TIME-RANGE",
                    "Time range",
                    column_targets(filterable_dataset_ids, "accident_date"),
                    excluded_except(all_charts, filterable_charts),
                ),
                select_filter(
                    state_filter_id,
                    "State",
                    column_targets(filterable_dataset_ids, "state_code"),
                    excluded_except(all_charts, filterable_charts),
                ),
                select_filter(
                    "NATIVE_FILTER-KPI2-COUNTY",
                    "County",
                    column_targets(filterable_dataset_ids, "county_name"),
                    excluded_except(all_charts, filterable_charts),
                    cascade_parent_ids=[state_filter_id],
                ),
                select_filter(
                    "NATIVE_FILTER-KPI2-SEVERITY",
                    "Severity",
                    column_targets(filterable_dataset_ids, "severity_level"),
                    excluded_except(all_charts, filterable_charts),
                ),
                select_filter(
                    "NATIVE_FILTER-KPI2-WEATHER",
                    "Weather condition",
                    column_targets(filterable_dataset_ids, "weather_condition_name"),
                    excluded_except(all_charts, filterable_charts),
                ),
                select_filter(
                    "NATIVE_FILTER-KPI2-ROAD-SIGNAL",
                    "Primary road signal",
                    column_targets(filterable_dataset_ids, "primary_road_signal"),
                    excluded_except(all_charts, filterable_charts),
                ),
            ]
            json_metadata["chart_configuration"] = {
                chart.id: {
                    "id": chart.id,
                    "crossFilters": {
                        "scope": "global",
                        "chartsInScope": [target.id for target in filterable_charts],
                    },
                }
                for chart in [
                    charts_by_name["KPI - KPI2 Duration by Weather"],
                    charts_by_name["KPI - KPI2 Duration by Severity and Road Signal"],
                    charts_by_name["KPI - KPI2 Top Counties by Accident Count"],
                ]
            }
            return json_metadata

        if DASHBOARD_KEY == "kpi3":
            dashboard3_chart_names = [
                "KPI - KPI3 Bad-Air AQI Share",
                "KPI - KPI3 Bad-Air Share Trend",
                "KPI - KPI3 Counties by Bad-Air Share",
                "KPI - KPI3 Bad-Air by Defining Parameter",
            ]
            filterable_charts = [charts_by_name[name] for name in dashboard3_chart_names]
            filterable_dataset_ids = sorted({chart.datasource_id for chart in filterable_charts})
            state_filter_id = "NATIVE_FILTER-KPI3-STATE"

            json_metadata["cross_filters_enabled"] = True
            json_metadata["native_filter_configuration"] = [
                time_filter(
                    "NATIVE_FILTER-KPI3-TIME-RANGE",
                    "Time range",
                    column_targets(filterable_dataset_ids, "observation_date"),
                    excluded_except(all_charts, filterable_charts),
                ),
                select_filter(
                    state_filter_id,
                    "State",
                    column_targets(filterable_dataset_ids, "state_code"),
                    excluded_except(all_charts, filterable_charts),
                ),
                select_filter(
                    "NATIVE_FILTER-KPI3-COUNTY",
                    "County",
                    column_targets(filterable_dataset_ids, "county_name"),
                    excluded_except(all_charts, filterable_charts),
                    cascade_parent_ids=[state_filter_id],
                ),
                select_filter(
                    "NATIVE_FILTER-KPI3-DEFINING-PARAMETER",
                    "Defining parameter",
                    column_targets(filterable_dataset_ids, "defining_parameter_name"),
                    excluded_except(all_charts, filterable_charts),
                ),
            ]
            json_metadata["chart_configuration"] = {
                chart.id: {
                    "id": chart.id,
                    "crossFilters": {
                        "scope": "global",
                        "chartsInScope": [target.id for target in filterable_charts],
                    },
                }
                for chart in [
                    charts_by_name["KPI - KPI3 Counties by Bad-Air Share"],
                    charts_by_name["KPI - KPI3 Bad-Air by Defining Parameter"],
                ]
            }
            return json_metadata

        if DASHBOARD_KEY != "kpi4":
            return json_metadata

        dashboard4_chart_names = [
            "KPI - AQI Accident Count Correlation",
            "KPI - AQI Duration Correlation",
            "KPI - AQI Severity Correlation",
            "KPI - AQI vs Accident Count Scatter",
            "KPI - AQI vs Duration Scatter",
            "KPI - State AQI Accident Correlation Ranking",
            "KPI - Accidents and AQI Monthly Comparison",
        ]
        filterable_charts = [charts_by_name[name] for name in dashboard4_chart_names]
        filterable_dataset_ids = sorted({chart.datasource_id for chart in filterable_charts})

        json_metadata["cross_filters_enabled"] = True
        json_metadata["native_filter_configuration"] = [
            time_filter(
                "NATIVE_FILTER-KPI4-TIME-RANGE",
                "Time range",
                column_targets(filterable_dataset_ids, "metric_month"),
                excluded_except(all_charts, filterable_charts),
            ),
            select_filter(
                "NATIVE_FILTER-KPI4-STATE",
                "State",
                column_targets(filterable_dataset_ids, "state_code"),
                excluded_except(all_charts, filterable_charts),
            ),
        ]
        json_metadata["chart_configuration"] = {
            chart.id: {
                "id": chart.id,
                "crossFilters": {
                    "scope": "global",
                    "chartsInScope": [target.id for target in filterable_charts],
                },
            }
            for chart in [
                charts_by_name["KPI - AQI vs Accident Count Scatter"],
                charts_by_name["KPI - AQI vs Duration Scatter"],
                charts_by_name["KPI - State AQI Accident Correlation Ranking"],
                charts_by_name["KPI - Accidents and AQI Monthly Comparison"],
            ]
        }
        return json_metadata

    count_chart = charts_by_name["KPI - KPI1 Accident Count"]
    trend_chart = charts_by_name["KPI - KPI1 Accident Count Trend"]
    hour_chart = charts_by_name["KPI - KPI1 Accidents by Weekday and Hour"]
    severity_chart = charts_by_name["KPI - KPI1 Accidents by Severity Over Time"]
    county_chart = charts_by_name["KPI - KPI1 Top Counties by Accident Count"]

    filterable_charts = [count_chart, trend_chart, hour_chart, severity_chart, county_chart]
    filterable_dataset_ids = sorted({chart.datasource_id for chart in filterable_charts})

    state_filter_id = "NATIVE_FILTER-KPI1-STATE"
    county_filter_id = "NATIVE_FILTER-KPI1-COUNTY"

    json_metadata["cross_filters_enabled"] = True
    json_metadata["native_filter_configuration"] = [
        time_filter(
            "NATIVE_FILTER-KPI1-TIME-RANGE",
            "Time range",
            column_targets(filterable_dataset_ids, "accident_date"),
            excluded_except(all_charts, filterable_charts),
        ),
        select_filter(
            state_filter_id,
            "State",
            column_targets(filterable_dataset_ids, "state_code"),
            excluded_except(all_charts, filterable_charts),
        ),
        select_filter(
            county_filter_id,
            "County",
            column_targets(filterable_dataset_ids, "county_name"),
            excluded_except(all_charts, filterable_charts),
            cascade_parent_ids=[state_filter_id],
        ),
        select_filter(
            "NATIVE_FILTER-KPI1-SEVERITY",
            "Severity",
            column_targets(filterable_dataset_ids, "severity_level"),
            excluded_except(all_charts, filterable_charts),
        ),
    ]
    json_metadata["chart_configuration"] = {
        severity_chart.id: {
            "id": severity_chart.id,
            "crossFilters": {
                "scope": "global",
                "chartsInScope": [chart.id for chart in filterable_charts],
            },
        },
        county_chart.id: {
            "id": county_chart.id,
            "crossFilters": {
                "scope": "global",
                "chartsInScope": [chart.id for chart in filterable_charts],
            },
        },
    }

    return json_metadata


app = create_app()
app.config["MCP_DEV_USERNAME"] = USERNAME

with app.app_context():
    from superset import db
    from superset.extensions import security_manager
    from superset.models.dashboard import Dashboard
    from superset.models.slice import Slice

    user = db.session.query(security_manager.user_model).filter_by(username=USERNAME).one_or_none()
    if user is None:
        raise RuntimeError(f"Superset user '{USERNAME}' not found.")
    g.user = user

    spec = DASHBOARDS[DASHBOARD_KEY]
    resolved_sections = []
    all_charts = []
    charts_by_name = {}

    for row in spec["sections"]:
        resolved_row = []
        for item in row:
            chart = (
                db.session.query(Slice)
                .filter_by(slice_name=item["name"])
                .order_by(Slice.id.desc())
                .first()
            )
            if chart is None:
                raise RuntimeError(f"Required chart not found: {item['name']}")
            resolved_item = dict(item)
            resolved_item["chart"] = chart
            resolved_row.append(resolved_item)
            all_charts.append(chart)
            charts_by_name[chart.slice_name] = chart
        resolved_sections.append(resolved_row)

    dashboard = db.session.query(Dashboard).filter_by(dashboard_title=spec["title"]).one_or_none()
    layout = build_layout(resolved_sections)
    json_metadata = build_json_metadata(all_charts, charts_by_name)

    if dashboard is None:
        dashboard = Dashboard()
        dashboard.dashboard_title = spec["title"]
        dashboard.description = spec["description"]
        dashboard.published = True
        dashboard.owners = [user]
        dashboard.position_json = json.dumps(layout)
        dashboard.json_metadata = json.dumps(json_metadata)
        dashboard.slices = all_charts
        db.session.add(dashboard)
    else:
        dashboard.description = spec["description"]
        dashboard.published = True
        dashboard.owners = [user]
        dashboard.position_json = json.dumps(layout)
        dashboard.json_metadata = json.dumps(json_metadata)
        dashboard.slices = all_charts

    db.session.commit()

    print(json.dumps(
        {
            "dashboard_id": dashboard.id,
            "dashboard_title": dashboard.dashboard_title,
            "dashboard_url": f"{HOST_BASE_URL}/superset/dashboard/{dashboard.slug or dashboard.id}/",
            "charts": [
                {
                    "id": chart.id,
                    "name": chart.slice_name,
                    "viz_type": chart.viz_type,
                    "url": f"{HOST_BASE_URL}/explore/?slice_id={chart.id}",
                }
                for chart in all_charts
            ],
        },
        indent=2,
    ))
PY
