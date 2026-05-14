# Superset Handoff

## Current State

- PostgreSQL warehouse is already up and treated as ready.
- Apache Superset is integrated into the existing Compose project as an optional `tools` service.
- Superset is reachable from the host at:
  - `http://localhost:18088`
- Default local admin credentials come from `infra/compose/.env`.
- The `dw` database is already registered in Superset.

## Relevant Commands

From project root:

```bash
./scripts/superset-up.sh
./scripts/superset-register-dw.sh
./scripts/superset-create-proof-dashboard.sh
./scripts/superset-logs.sh
./scripts/superset-down.sh
```

## What Was Proven

The following was created successfully from code:

- virtual dataset: `dw_dim_time_preview`
- chart: `DW Dim Time Preview Chart`
- dashboard: `DW Superset Proof Dashboard`

Host URLs:

- dataset: `http://localhost:18088/explore/?datasource_type=table&datasource_id=1`
- chart: `http://localhost:18088/explore/?slice_id=1`
- dashboard: `http://localhost:18088/superset/dashboard/2/`

This proves:

- Superset can reach the warehouse over the Compose network
- Superset assets can be provisioned from code
- dashboards are usable from the desktop GUI

## Important Fix Already Applied

The first proof chart failed in the dashboard with:

- `Found invalid orderby options`

Cause:

- the saved table chart used a display label in sort config instead of a real dataset column

Resolution:

- `scripts/superset-create-proof-dashboard.sh` was updated to avoid that invalid table sort config
- rerunning the script repaired the live proof dashboard

## Main Files Added

- `docs/superset.md`
- `infra/platform/superset/bootstrap.sh`
- `infra/platform/superset/superset_config.py`
- `scripts/superset-up.sh`
- `scripts/superset-down.sh`
- `scripts/superset-logs.sh`
- `scripts/superset-fix-perms.sh`
- `scripts/superset-register-dw.sh`
- `scripts/superset-create-proof-dashboard.sh`

## Recommended Next Session Goal

Move from the proof dashboard to the first real interactive dashboard.

Most likely path:

1. choose the first user-facing question set
2. decide whether the first dashboard uses v1, v2, or both
3. create Superset datasets/views tailored for interactive filtering
4. add filters for time, state, county, severity, weather, AQI category, and defining parameter
5. build the first meaningful dashboard slice

## Modeling Note

The DW already contains the required dimensions for interactivity. The next work is BI-layer design in Superset, not warehouse redesign.
