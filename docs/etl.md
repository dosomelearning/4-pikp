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

## Road-Condition Cardinality Observation
For `dim_road_condition`, we model combinations of 13 boolean source flags:
- Theoretical maximum combinations: `2^13 = 8192`.
- Observed in full US-Accidents source (`7,728,394` rows): **344 distinct combinations**.

Implemented loader:
- `scripts/etl/populate-dim-road-condition.sh`

Notes:
- Null/empty values are normalized to `false` for these flags.
- Distinct combination count grows quickly at first and then saturates, which confirms low practical cardinality compared to the theoretical maximum.

## Current Loaded State (US-Accidents Dimensions)
Verified after running SQL/Python ETL scripts:

- `dw.dim_time`: `96,432` rows
- `dw.dim_severity`: `4` rows
- `dw.dim_weather_condition`: `144` rows
- `dw.dim_road_condition`: `344` rows
- `dw.dim_location`: `1,121,149` rows

Location split in `dw.dim_location`:
- Detailed members (`D|...`): `1,118,035`
- County-level members (`C|...`): `3,114`

All loaded rows in these dimensions are currently marked as `is_current = true`.

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
- Keep air ETL reusable for additional `daily_aqi_by_county_YYYY.csv` files (same script set, different input path).
- Add/maintain validation checks after each ETL phase (row counts, duplicate NK checks, measure range checks).
- Keep Pentaho artifacts for reference only unless explicitly revived later.

## Air ETL (Implemented)
Air ETL is implemented in SQL+Python with explicit `air` naming in scripts:
- `scripts/etl/populate-air-dim-location.sh`
- `scripts/etl/populate-air-dim-aqi-category.sh`
- `scripts/etl/populate-air-dim-defining-parameter.sh`
- `scripts/etl/check-air-dimensions.sh`
- `scripts/etl/populate-air-fact-daily.sh`
- `scripts/etl/run-air-etl.sh`
- `scripts/etl/run-air-etl-all.sh`

Source coverage strategy:
- Accidents ETL uses a single consolidated source file:
  - `raw/archive/US_Accidents_March23.csv`
- Air ETL uses a yearly file family:
  - `raw/daily_aqi_by_county_YYYY.csv`
- Conformance target range (based on loaded accidents fact range in `dw.fact_accident`):
  - accidents `start_time` range: `2016-01-14` to `2023-03-31`
  - therefore air yearly inputs should be processed for years `2016..2023`

Current source availability status (`raw/`):
- `daily_aqi_by_county_2016.csv` present
- `daily_aqi_by_county_2017.csv` present
- `daily_aqi_by_county_2018.csv` present
- `daily_aqi_by_county_2019.csv` present
- `daily_aqi_by_county_2020.csv` present
- `daily_aqi_by_county_2021.csv` present
- `daily_aqi_by_county_2022.csv` present
- `daily_aqi_by_county_2023.csv` present
- Missing yearly air input files for target range `2016..2023`: **none**

Execution flow:
1. Load air dimensions (including county-level location members in shared `dw.dim_location`).
2. Run dimension checks (`check-air-dimensions.sh`).
3. Load air facts (`populate-air-fact-daily.sh`), or run all via `run-air-etl.sh` with `RUN_FACT=1`.
4. For multi-year processing, use `run-air-etl-all.sh` to iterate year files and invoke per-file idempotent ETL.

Conformance and safety notes:
- Existing accidents ETL and schema behavior are unchanged.
- Shared conformed dimensions are reused:
  - `dw.dim_time` with daily anchor `HH=00` for air facts.
  - `dw.dim_location` county members using `location_nk = C|<county>|<state_abbrev>|US`.
- Air scripts are additive/idempotent (insert missing current members, no destructive rewrites).
- Batch strategy is intentionally idempotent per file so reruns do not break dimensions or duplicate facts.
- Logging behavior:
  - periodic progress output is enabled by default with `PROGRESS_EVERY=5000`,
  - skip reasons are printed as summarized counters,
  - top exception categories are printed via `TOP_ISSUES` (default `10`), e.g. unmapped state names.

What is still missing:
- Run and validate full multi-year air ETL pass (`2016..2023`) with `run-air-etl-all.sh` and persist final aggregate row counts/check outcomes in this document.

Observed run results (sample file `raw/daily_aqi_by_county_2017.csv`):
- `dim_location` county members extracted from air source: `1,027` NKs, all resolvable in current `dw.dim_location` after load (`missing_in_dim_location = 0`).
- `dim_aqi_category`: `7` current rows (includes explicit `unknown` member).
- `dim_defining_parameter`: `6` current rows (includes explicit `unknown` member).
- `fact_air_quality_daily`: `326,231` rows loaded.

Air fact skip profile (same run):
- Skipped rows: `570`
- Skip reason: `unknown_state_name = 570`
- Unmapped source value identified: `Country Of Mexico` (outside US scope for this model).

## Fact Load Skip Logic (Current)
`scripts/etl/populate-fact-accident.sh` stages and validates source rows before insert into `dw.fact_accident`.
Progress lines (`[progress] rows=... staged=... skipped=...`) are **cumulative totals since script start**, not per-interval deltas.

Rows are currently skipped for these reasons:
- `missing_id`: source `ID` missing.
- `severity`: invalid or missing `Severity`.
- `time_parse`: `Start_Time`/`End_Time` cannot be parsed.
- `time_order`: `End_Time < Start_Time`.
- `coords`: missing/invalid required start coordinates (or invalid numeric parsing).
- `location_detail`: insufficient fields to build detailed location NK.
- `location_county`: insufficient fields to build county-level location NK.
- `weather_missing_mapped_unknown`: missing weather condition value mapped to `dim_weather_condition` unknown member (informational counter, not skipped).

Important note:
- In the current star schema, `fact_accident.weather_condition_key` is `NOT NULL`.
- We now handle missing weather with an explicit unknown dimension member:
  - `dim_weather_condition.weather_condition_nk = 'unknown'`
  - `dim_weather_condition.weather_condition_name = 'Unknown'`
- Fact rows with missing weather are mapped to that member instead of being skipped.
- Timestamp parser in fact ETL now normalizes long fractional tails (e.g. `.000000000`) to avoid unnecessary time-parse skips.

## Fact Timestamp Parse Investigation (Accidents)
This issue was important because the first full fact run skipped too many records and most of them were tagged as `time_parse`.

### Run #1 (Before Parser Fix / Before Unknown-Weather Mapping)
Observed output:
- Rows scanned: `7,728,394`
- Staged: `6,889,092`
- Skipped: `839,302`
- Skip reasons:
  - `time_parse = 682,322`
  - `weather = 156,980`
  - all other skip reasons = `0`
- Insert result:
  - `COPY 6889092`
  - `INSERT 0 6839695`
  - final `dw.fact_accident` row count after run: `6,889,092`

Reasoning from this profile:
- `time_parse` dominated skips and increased sharply in later parts of the file.
- This pattern suggested a systematic format issue (not random bad records).

### Role of Helper Investigation Script
Helper script:
- `scripts/etl/inspect-fact-time-parse-skips.sh`

Purpose:
- Re-run the same timestamp parser logic as fact ETL.
- Print concrete failing timestamp samples and top recurring unparsed values.

Key finding:
- Failing values contained nanosecond tails, e.g.:
  - `2017-07-23 04:21:01.000000000`
- Original parser accepted microseconds (`%f`, up to 6 digits), so 9-digit fractional seconds failed.

### Fix Applied
In `scripts/etl/populate-fact-accident.sh`:
- normalize timestamp prefix from left to right (`YYYY-MM-DD HH:MM:SS`),
- truncate fractional part to 6 digits when longer than 6,
- parse normalized value.

Helper script was updated to the same parser so diagnostics and ETL behavior stay aligned.

Validation of fix on problematic late-file slice:
- `SKIP_ROWS=3500000 ROW_LIMIT=4100000 scripts/etl/inspect-fact-time-parse-skips.sh`
- Result: `parse_fail_rows=0` for that scanned slice.

### Run #2 (After Parser Fix, in-progress comparison checkpoint)
At `rows=4,000,000`:
- Run #1 skipped: `172,487`
- Run #2 skipped: `79,223`

This confirms the parser fix materially reduced skip growth in the same processing range.

### Run #3 (After Parser Fix + Unknown-Weather Mapping)
Final output:
- Rows scanned: `7,728,394`
- Staged: `7,728,394`
- Skipped: `0`
- Skip reasons:
  - `time_parse = 0`
  - `weather_missing_mapped_unknown = 173,459` (mapped to unknown, not skipped)
  - all other skip reasons = `0`
- Insert result on rerun:
  - `COPY 7728394`
  - `INSERT 0 173459` (backfilled rows previously missing due to weather)
- Final `dw.fact_accident` row count: `7,728,394`

Conclusion:
- Timestamp normalization + unknown-member handling achieved full fact coverage for the dataset while preserving mandatory FK constraints.

## Weather Missing-Value Investigation
Question raised:
- Why were weather gaps not caught during dimension extraction?

Answer:
- Dimension extraction for weather originally took only non-null `Weather_Condition` values and built `dim_weather_condition` from those.
- This is correct for collecting known category members, but it does not by itself guarantee fact completeness because fact FK is mandatory (`NOT NULL`).
- The missing piece was explicit unknown-member handling for null weather values at fact-load time.

Helper investigation:
- `scripts/etl/inspect-fact-weather-skips.sh` was added to profile missing weather on rows that otherwise pass all fact validations.
- It reports sample rows and distributions (state/source/year) to confirm the pattern is source-data incompleteness, not parser failure.

### Unknown Member Pattern (Important)
For mandatory fact FKs, dimension extraction from non-null source values is not enough.

Pattern used:
1. Create/ensure explicit unknown dimension member.
2. Map null/missing source value to that unknown NK during fact staging.
3. Resolve FK against current dimension rows as usual.

Applied for weather:
- Unknown member in dimension:
  - `weather_condition_nk = 'unknown'`
  - `weather_condition_name = 'Unknown'`
- Fact mapping:
  - if source `Weather_Condition` is null/empty, set `weather_nk = 'unknown'`

Why this matters:
- Preserves fact-row completeness while keeping `weather_condition_key` non-null.
- Keeps missingness explicit and analyzable (`Unknown` bucket) instead of silently dropping records.

Execution order requirement:
- Run `populate-dim-weather-condition.sh` before `populate-fact-accident.sh` so unknown member is guaranteed to exist for FK lookup.
