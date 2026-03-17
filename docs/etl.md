# ETL Strategy (SQL + Python)

## Context
This project loads two US datasets into a warehouse-style star model in PostgreSQL:
- US Accidents (Kaggle)
- US Air Quality (EPA AQS daily by county)

We initially attempted to implement ETL with Pentaho (WebSpoon), then switched direction.

## What Happened With Pentaho
We spent significant time debugging transformation behavior for `accidents_dimensions.ktr`, including:
- file save permission issues inside container mounts,
- brittle XML/step configuration edits,
- step validation/runtime mismatches,
- long-running `InsertUpdate` behavior on very large CSV input,
- misleading progress characteristics (apparent throughput decay / poor observability).

A critical indicator was that `dim_time` repeatedly stalled around the same count during Pentaho-driven ingestion, while independent checks showed many more unique hour keys should be available early in the file.

## Decision
We decided to stop spending time on Pentaho for this course project and move ETL implementation to:
- SQL (set-based loading in PostgreSQL), and
- Python (deterministic transforms + orchestration where SQL-only is not enough).

Reasoning:
- faster delivery,
- transparent and reproducible logic,
- easier debugging and validation,
- better fit for large-file processing and course constraints.

## First Practical Result
`dim_time` is now loaded with SQL `generate_series` via:
- `scripts/etl/populate-dim-time-generate-series.sh`

This script is idempotent (`ON CONFLICT DO NOTHING`) and quickly generates hourly rows for a configurable range.

## ETL Implementation Plan
1. Keep star schema DDL as source of truth in `naloga2/`.
2. Use SQL for dimensions where set-based generation/loading is straightforward (`dim_time`, small lookup dimensions).
3. Use Python for heavy source parsing and transformation logic from raw CSVs.
4. Load into staging or direct dimension/fact tables with explicit mapping rules from `naloga2/*_datasource.md`.
5. Add validation queries after each load step:
   - row counts,
   - FK null checks,
   - duplicate natural key checks,
   - basic range checks for measures.

## Conventions Going Forward
- Prefer idempotent loads where feasible.
- Keep scripts non-interactive and runnable from project root.
- Keep units and semantics aligned with documented model decisions:
  - American units,
  - Type 2 SCD policy where selected,
  - shared conformed dimensions (`dim_time`, `dim_location`) across datasets.

## Next Steps
- Implement accidents ETL fully in SQL+Python (dimensions first, then facts).
- Implement air-quality ETL in SQL+Python with conformed keys.
- Keep Pentaho artifacts for reference only unless explicitly revived later.
