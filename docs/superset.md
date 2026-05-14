# Apache Superset

Superset is the dashboarding layer for this project. It runs as an optional container in the existing Compose project and joins the same Docker network as PostgreSQL, so it can reach the warehouse directly by service name.

## What This Setup Provides

- Host access to the Superset UI from your desktop.
- Persistent local Superset state under `data/superset/` so users, saved connections, charts, and dashboards survive container restarts.
- A local bootstrap flow that upgrades Superset metadata, ensures the admin user exists, and starts the web UI automatically.

## Start, Stop, Logs

From project root:

```bash
./scripts/superset-up.sh
./scripts/superset-register-dw.sh
./scripts/superset-create-proof-dashboard.sh
./scripts/superset-logs.sh
./scripts/superset-down.sh
```

Superset is exposed on:

- `http://localhost:18088`

## Login

Default local credentials come from `infra/compose/.env`:

- username: `admin`
- password: `admin`

Change these in `infra/compose/.env` before startup if needed.

## Connect Superset to the Warehouse

Because Superset runs inside the same Compose network, use the PostgreSQL service name, not `localhost`.

Use this SQLAlchemy URI when adding the project warehouse in the Superset GUI:

```text
postgresql+psycopg2://dw_user:dw_pass@postgres:5432/dw
```

Adjust credentials if your local `infra/compose/.env` differs.

To register the warehouse from code instead of through the GUI, run:

```bash
./scripts/superset-register-dw.sh
```

Defaults:

- Superset database name: `dw`
- Warehouse URI: `postgresql+psycopg2://dw_user:dw_pass@postgres:5432/dw`

Overrides are supported through environment variables:

- `SUPERSET_DATABASE_NAME`
- `SUPERSET_DW_URI`

## Proof Dashboard

To create a minimal code-driven proof dashboard against the warehouse:

```bash
./scripts/superset-create-proof-dashboard.sh
```

It creates or updates:

- virtual dataset: `dw_dim_time_preview`
- chart: `DW Dim Time Preview Chart`
- dashboard: `DW Superset Proof Dashboard`

The script prints the dataset, chart, and dashboard URLs so you can open the result directly in the GUI.

## Persistence and Scope

- Superset application metadata is stored locally in `data/superset/`.
- The setup is meant for local coursework/dashboard work, not production hardening.
- PostgreSQL in `dw` remains the analytical source; Superset metadata is separate from warehouse fact/dimension tables.
