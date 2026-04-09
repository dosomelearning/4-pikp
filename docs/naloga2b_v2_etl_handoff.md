# Naloga2b V2 ETL Handoff (Next Session Context Anchor)

## Purpose
This document preserves full working context for the next Codex session, so we can continue implementing ETL without re-explaining design decisions.

## Current Status (Confirmed)
- `naloga2b` was created as a parallel track to `naloga2`.
- Migration was created and applied successfully to an existing DB.
- New v2 tables are present in schema `dw`:
  - `dim_county`
  - `dim_streetcity`
  - `fact_accident_v2`
  - `fact_air_quality_daily_v2`
- Existing v1 tables remain intact and must remain untouched.

## Non-Negotiable Rules
1. Do not modify `naloga2/`.
2. Do not change existing v1 ETL behavior or scripts.
3. Build new ETL logic as additive-only for v2 tables.
4. Keep side-by-side comparability between v1 and v2.
5. Keep SQL + docs + diagram aligned after each change.

## Why We Chose This Design
- We are preserving invested effort in v1 and not discarding working implementation.
- We want both approaches clearly demonstrated and measurable.
- We follow separate concerns:
  - v1 pipelines keep loading v1 tables,
  - new v2 pipelines load only v2 tables/dims.
- We follow add-only extension style (open-for-extension mindset):
  - introduce new objects/pipelines,
  - avoid destructive rewrites.

## Architecture Summary (v1 vs v2)

### Shared dimensions (used by both)
- `dw.dim_time`
- `dw.dim_weather_condition`
- `dw.dim_road_condition`
- `dw.dim_severity`
- `dw.dim_aqi_category`
- `dw.dim_defining_parameter`

### v1 path (legacy)
- `dw.dim_location`
- `dw.fact_accident`
- `dw.fact_air_quality_daily`

### v2 path (new)
- `dw.dim_county`
- `dw.dim_streetcity` (`county_key` -> `dim_county`)
- `dw.fact_accident_v2`
- `dw.fact_air_quality_daily_v2`

## FK Style Decision
In SQL we intentionally use inline `REFERENCES` syntax for FKs.

Example:
```sql
county_key bigint NOT NULL REFERENCES dw.dim_county(county_key)
```

This is explicit FK creation in PostgreSQL and is equivalent in semantics to named table-level FK constraints.

## Files That Define Source of Truth
Primary contract:
- `naloga2b/ARCHITECTURE_DECISIONS.md`

DDL:
- `naloga2b/us_accidents_star_schema.sql`
- `naloga2b/us_air_quality_star_schema.sql`

Incremental migration (existing DBs):
- `naloga2b/migrations/001_add_v2_location_and_facts.sql`

Datasource docs:
- `naloga2b/us_accidents_datasource.md`
- `naloga2b/us_air_quality_datasource.md`

Diagram:
- `naloga2b/Ekipa12_Naloga2b.dot`
- `docs/img/Ekipa12_Naloga2b.png`

Dot tooling reference:
- `naloga2b/GRAPHVIZ_DOT_USAGE.md`

## Commits That Captured This Baseline
- `b582aa6` Add naloga2b dual-track warehouse design and migration
- `c03f77c` Ignore Codex CLI marker file

## Next Session Goal: Implement V2 ETL (Additive)
Implement new ETL scripts for v2 only, without changing existing ETL scripts.

### Recommended script family (new files)
Under `scripts/etl/`, add v2-specific scripts with clear naming, for example:
- `populate-v2-dim-county.sh`
- `populate-v2-dim-streetcity.sh`
- `populate-v2-fact-accident.sh`
- `populate-v2-fact-air-quality-daily.sh`
- `run-v2-etl.sh` (optional orchestrator)
- `check-v2-integrity.sh` (validation checks)

### Execution Syntax (Implemented)
From repository root:

```bash
# Full v2 flow (dims + facts)
./scripts/etl/run-v2-etl.sh

# Integrity check for v2 dimensions/facts and v1-v2 row parity
./scripts/etl/check-v2-integrity.sh
```

Optional examples:

```bash
# Run only v2 dimensions (skip both fact loads)
RUN_FACT_ACCIDENT_V2=0 RUN_FACT_AIR_V2=0 ./scripts/etl/run-v2-etl.sh

# Run with explicit air year window
AIR_START_YEAR=2016 AIR_END_YEAR=2023 ./scripts/etl/run-v2-etl.sh
```

### Required behavior
- Idempotent inserts where possible.
- Preserve source natural keys in v2 facts (`source_accident_id`, state/county/date triplet).
- No update/delete against v1 facts.
- Validate FK resolvability and row counts explicitly after each load.

### Critical mapping concerns to handle
- County conformance for accidents (source has no county code):
  - use robust normalized county/state/country mapping,
  - include explicit alias handling (e.g., `St.` vs `Saint`) where needed.
- Air v2 should prefer code-based county identity (`State Code` + `County Code`) for `dim_county` membership.

## Validation Expectations for V2
At minimum, verify:
1. `fact_accident_v2` row count vs expected staged rows.
2. `fact_air_quality_daily_v2` row count vs expected staged rows.
3. FK completeness (no unresolved `streetcity_key`/`county_key` joins in inserted rows).
4. Comparable aggregate outputs between v1 and v2 at county/day level for sanity checks.

## Session Bootstrap Tip
In the next session, run `get ready` first (project convention). This document is intentionally under `docs/` so it is included in that readiness scan.

## Final Intent Statement
We are not replacing v1. We are proving v2 in parallel.
Both models are valid; the objective is clear demonstration, stable comparison, and maintainable evolution.
