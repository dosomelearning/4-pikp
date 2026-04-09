# ETL Scripts Usage

Operational usage for ETL runs.

All commands below assume you are in project root:
- `/home/raven/data/doc/privat/uni/univaje/4-pikp`

## Prerequisites

- Infrastructure is up and PostgreSQL is reachable:

```bash
./scripts/infra-up.sh
./scripts/pg-smoketest.sh
```

- Required compose env file exists:
  - `infra/compose/.env`
- Raw datasets are present under `raw/`.

## 1) Run Full Legacy Cycle (Analysis + v1 ETL + Validation)

This is the highest-level end-to-end runner for the legacy/v1 model.

Default:

```bash
./scripts/run-full-etl-cycle.sh
```

With explicit 4-char correlation ID + validation verbosity:

```bash
CORRELATION_ID=A1B2 \
SHOW_CHECKED=non_compliant \
./scripts/run-full-etl-cycle.sh
```

Notes:
- If `CORRELATION_ID` is omitted, runner generates one.
- For this script, correlation ID must normalize to exactly 4 alphanumeric chars.

## 2) Run Legacy ETL by Domain

### 2.1 Accidents ETL (v1)

Default:

```bash
./scripts/etl/run-accidents-etl.sh
```

With overrides:

```bash
CORRELATION_ID=ETL01 \
RAW_CSV=./raw/archive/US_Accidents_March23.csv \
PROGRESS_EVERY=250000 \
TIME_START='2016-01-01 00:00:00' \
TIME_END='2026-12-31 23:00:00' \
ROW_LIMIT=0 \
./scripts/etl/run-accidents-etl.sh
```

### 2.2 Air ETL (single year, v1)

Default (dimensions only):

```bash
./scripts/etl/run-air-etl.sh
```

Single-year with fact load enabled:

```bash
CORRELATION_ID=ETL01 \
RAW_CSV=./raw/daily_aqi_by_county_2019.csv \
RUN_FACT=1 \
PROGRESS_EVERY=5000 \
ROW_LIMIT=0 \
TOP_ISSUES=10 \
./scripts/etl/run-air-etl.sh
```

### 2.3 Air ETL (all years, v1)

Default:

```bash
./scripts/etl/run-air-etl-all.sh
```

Custom range and strict missing-file handling:

```bash
CORRELATION_ID=ETL01 \
AIR_DIR=./raw \
AIR_START_YEAR=2016 \
AIR_END_YEAR=2023 \
RUN_FACT=1 \
MISSING_FILE_MODE=error \
PROGRESS_EVERY=5000 \
TOP_ISSUES=10 \
./scripts/etl/run-air-etl-all.sh
```

`MISSING_FILE_MODE`:
- `warn` (default): skip missing year files.
- `error`: fail fast on missing files or year-level failures.

## 3) Run v2 ETL (County/StreetCity + v2 Facts)

Main v2 runner:

```bash
./scripts/etl/run-v2-etl.sh
```

Typical full v2 run:

```bash
CORRELATION_ID=V2A1 \
ACCIDENTS_CSV=./raw/archive/US_Accidents_March23.csv \
AIR_DIR=./raw \
AIR_START_YEAR=2016 \
AIR_END_YEAR=2023 \
RULES_JSON=./scripts/analysis/rules.json \
PROGRESS_EVERY_ACCIDENTS=250000 \
PROGRESS_EVERY_AIR=5000 \
RUN_FACT_ACCIDENT_V2=1 \
RUN_FACT_AIR_V2=1 \
ROW_LIMIT_ACCIDENTS=0 \
ROW_LIMIT_AIR=0 \
TOP_ISSUES=10 \
MISSING_FILE_MODE=warn \
./scripts/etl/run-v2-etl.sh
```

Dry-run/test-friendly variants:

```bash
# Dimensions only (skip both v2 facts)
RUN_FACT_ACCIDENT_V2=0 RUN_FACT_AIR_V2=0 ./scripts/etl/run-v2-etl.sh

# Accidents fact only
RUN_FACT_ACCIDENT_V2=1 RUN_FACT_AIR_V2=0 ./scripts/etl/run-v2-etl.sh

# Air fact only
RUN_FACT_ACCIDENT_V2=0 RUN_FACT_AIR_V2=1 ./scripts/etl/run-v2-etl.sh
```

## 4) Run v2 Integrity Checks

After v2 ETL, validate row counts and FK integrity:

```bash
./scripts/etl/check-v2-integrity.sh
```

## 5) Run ETL Step-by-Step (Low-Level Scripts)

These are useful for targeted reruns/debugging.

### 5.1 Legacy dimensions/facts

```bash
./scripts/etl/populate-dim-time-generate-series.sh '2016-01-01 00:00:00' '2026-12-31 23:00:00'
./scripts/etl/populate-dim-severity.sh ./raw/archive/US_Accidents_March23.csv
./scripts/etl/populate-dim-road-condition.sh ./raw/archive/US_Accidents_March23.csv
./scripts/etl/populate-dim-weather-condition.sh ./raw/archive/US_Accidents_March23.csv
./scripts/etl/populate-dim-location.sh ./raw/archive/US_Accidents_March23.csv
./scripts/etl/populate-fact-accident.sh ./raw/archive/US_Accidents_March23.csv
```

### 5.2 Air dimensions/fact (v1)

```bash
./scripts/etl/populate-air-dim-location.sh ./raw/daily_aqi_by_county_2019.csv
./scripts/etl/populate-air-dim-aqi-category.sh ./raw/daily_aqi_by_county_2019.csv
./scripts/etl/populate-air-dim-defining-parameter.sh ./raw/daily_aqi_by_county_2019.csv
./scripts/etl/check-air-dimensions.sh ./raw/daily_aqi_by_county_2019.csv
./scripts/etl/populate-air-fact-daily.sh ./raw/daily_aqi_by_county_2019.csv
```

### 5.3 v2 dimensions/facts

```bash
./scripts/etl/populate-v2-dim-county.sh
./scripts/etl/populate-v2-dim-streetcity.sh ./raw/archive/US_Accidents_March23.csv
./scripts/etl/populate-v2-fact-accident.sh ./raw/archive/US_Accidents_March23.csv
./scripts/etl/populate-v2-fact-air-quality-daily.sh ./raw/daily_aqi_by_county_2019.csv
```

## 6) Logs and Correlation IDs

Log files are written under:
- `docs/logs/`

Typical patterns:
- `accidents_etl_YYYYMMDD_HHMMSS.log`
- `air_etl_YYYYMMDD_HHMMSS.log`
- `air_etl_all_YYYYMMDD_HHMMSS.log`
- `v2_etl_YYYYMMDD_HHMMSS.log`
- `AB12_full_etl_cycle_YYYYMMDD_HHMMSS.log`

If `CORRELATION_ID` is set for runners that support it, log files are prefixed:
- `AB12_v2_etl_...log`
- `AB12_air_etl_all_...log`
- etc.

Normalization rule for `CORRELATION_ID` in ETL runners:
- converted to uppercase
- stripped to alphanumeric (`A-Z0-9`)
- some scripts allow variable length after normalization; `run-full-etl-cycle.sh` requires exactly 4 chars.

## 7) Destructive Utility

Use with care (truncates all `dw` tables with `RESTART IDENTITY CASCADE`):

```bash
./scripts/etl/clear-dw-tables.sh
```
