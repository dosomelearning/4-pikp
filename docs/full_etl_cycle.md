# Full ETL Cycle

This document defines and records the full repeatable cycle:

1. clear DW tables
2. clear `docs/analysis.json`
3. run raw analysis (accidents + air)
4. run ETL (accidents, then air all-years)
5. run DB-vs-analysis validation

## Canonical Command Sequence

Run from repository root:

```bash
./scripts/etl/clear-dw-tables.sh
./scripts/analysis/analysis_json_clear.sh
./scripts/analysis/run-analysis-all.sh
./scripts/etl/run-accidents-etl.sh
./scripts/etl/run-air-etl-all.sh
SHOW_CHECKED=non_compliant ./scripts/analysis/validate-db-vs-analysis.sh
```

## Single-Command Orchestrator (With Correlation ID)

Run the full cycle in one command:

```bash
./scripts/run-full-etl-cycle.sh
```

Behavior:

- Generates a 4-char alphanumeric `CORRELATION_ID` automatically (if not provided).
- Passes `CORRELATION_ID` to analysis/ETL runners.
- Prefixes log filenames for runners that emit log files.
- Keeps original log naming unchanged when scripts are called individually without `CORRELATION_ID`.

Override correlation ID manually:

```bash
CORRELATION_ID=AB12 ./scripts/run-full-etl-cycle.sh
```

Configure validation console verbosity in orchestrated run:

```bash
SHOW_CHECKED=all ./scripts/run-full-etl-cycle.sh
```

Optional verbose validation trace:

```bash
SHOW_CHECKED=all ./scripts/analysis/validate-db-vs-analysis.sh
```

## Notes

- `run-analysis-all.sh` is expected to be long due to two full passes over the 7.7M-row accidents source.
- `run-accidents-etl.sh` can be quiet for long periods during `fact_accident` load (`COPY` + insert/index work in PostgreSQL).
- `run-air-etl-all.sh` runs per year (`2016..2023`) and logs each year boundary.
- Correlation-prefixed log naming is currently implemented for:
  - `scripts/analysis/run-analysis-all.sh`
  - `scripts/etl/run-accidents-etl.sh`
  - `scripts/etl/run-air-etl.sh`
  - `scripts/etl/run-air-etl-all.sh`
- Final integrity gate is validation status from:
  - `docs/analysis_validation.json`
  - console summary from `validate-db-vs-analysis.sh`

## Execution Record: 2026-03-26

Run intent: full cycle with analysis between reset and ETL.

- DW reset executed:
  - `./scripts/etl/clear-dw-tables.sh`
- analysis reset executed:
  - `./scripts/analysis/analysis_json_clear.sh`
- analysis executed:
  - `./scripts/analysis/run-analysis-all.sh`
  - completed at `2026-03-26T17:08:01+01:00`
  - log: `docs/logs/analysis_all_20260326_165404.log`
- accidents ETL:
  - `./scripts/etl/run-accidents-etl.sh`
  - completed at `2026-03-26T17:32:31+01:00`
  - log: `docs/logs/accidents_etl_20260326_170833.log`
  - key result: `fact_accident_rows = 7,728,394`
- air ETL all-years:
  - `./scripts/etl/run-air-etl-all.sh`
  - completed at `2026-03-26T17:36:36+01:00`
  - log: `docs/logs/air_etl_all_20260326_173303.log`
  - key result: `fact_air_quality_daily_rows = 2,599,493`
- validation:
  - `SHOW_CHECKED=non_compliant ./scripts/analysis/validate-db-vs-analysis.sh`
  - completed at `2026-03-26T17:37:03+01:00`
  - output: `docs/analysis_validation.json`
  - status: `compliant`
  - summary: `non_compliant=0`, `checked=65`
