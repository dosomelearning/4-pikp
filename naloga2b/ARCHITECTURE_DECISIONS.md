# Naloga2b Architecture Decisions (Source of Truth)

This document is the authoritative design baseline for `naloga2b`.

## Why `naloga2b` Exists

`naloga2b` is not a replacement of `naloga2`. It is an explicit side-by-side demonstration of two valid warehouse modeling approaches:

- v1: legacy star approach already implemented in `naloga2`
- v2: new location snowflake approach for clearer conformance

The project keeps both because prior engineering effort matters and remains useful for comparison and learning.

## Core Decision: Keep v1, Add v2

We keep all existing v1 structures and add new v2 structures.

- Existing v1 is preserved unchanged.
- New v2 objects are additive.
- No destructive migration is used.

This enables direct, measurable comparison between models (correctness, maintainability, query shape, ETL complexity, and performance).

## Separate Concerns Principle

Implementation is intentionally separated:

- Existing ETL continues to load v1 facts and dimensions.
- New ETL will load only new v2 dimensions and v2 facts.
- Legacy code paths do not need to be modified to introduce v2.

This is conceptually aligned with an add-only/open-for-extension style (often compared to Open/Closed thinking): we extend behavior by adding new structures instead of rewriting stable ones.

## Add-Only Migration Policy

For existing databases, use incremental migration scripts that only add new objects.

- Migration file: `naloga2b/migrations/001_add_v2_location_and_facts.sql`
- Allowed operations in migration:
  - `CREATE TABLE IF NOT EXISTS`
  - `CREATE INDEX IF NOT EXISTS`
  - `CREATE UNIQUE INDEX IF NOT EXISTS`
- Not allowed in migration:
  - dropping v1 tables
  - rewriting v1 table structure
  - destructive transformations

## v1/v2 Model Boundaries

### Shared dimensions (used by both v1 and v2)
- `dw.dim_time`
- `dw.dim_weather_condition`
- `dw.dim_road_condition`
- `dw.dim_severity`
- `dw.dim_aqi_category`
- `dw.dim_defining_parameter`

### v1-specific location path
- `dw.dim_location`
- `dw.fact_accident`
- `dw.fact_air_quality_daily`

### v2-specific location path
- `dw.dim_county`
- `dw.dim_streetcity`
- `dw.fact_accident_v2`
- `dw.fact_air_quality_daily_v2`

## Foreign Keys: Inline `REFERENCES`

In `naloga2b` SQL, foreign keys are defined inline using `REFERENCES`.

Example:

```sql
county_key bigint NOT NULL REFERENCES dw.dim_county(county_key)
```

This is an explicit FK definition in PostgreSQL (equivalent in semantics to a named table-level `CONSTRAINT ... FOREIGN KEY ...`).

Reason for this choice:
- concise DDL,
- readable column-local relationship definition,
- sufficient for this project scope.

## Development Rule Going Forward

When extending `naloga2b`:

1. Keep v1 behavior stable.
2. Add new v2 ETL and validation in separate scripts.
3. Keep docs and diagram synchronized with SQL.
4. Treat this document as the architecture contract.
