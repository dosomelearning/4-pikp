# Data Analysis Plan (Pre-ETL Explainability)

## Preamble: Intent, Scope, and Guardrails
- This document defines a **pre-ETL analysis layer** whose only input is raw source files.
- The analysis layer exists to produce measurable expectations in `docs/analysis.json` **before** ETL writes to DB tables.
- ETL results are then validated against those expectations after load.
- Assumption baseline is strict: raw datasets are sufficient; analysis must not rely on hidden hardcoded domain lists.

What this analysis layer must do:
- express expected counts, ranges, distinct-key cardinalities, and skip/exception profiles from raw data,
- discover required transformation dictionaries/sets from raw data first, persist them in `analysis.json`, and only then compute metrics,
- remain deterministic and repeatable across reruns.

What this analysis layer must not do:
- it must not modify DB data,
- it must not replace ETL scripts,
- it must not silently diverge from ETL rules,
- it must not hardcode source-specific lookup lists that can be discovered from raw files.

Critical project asymmetry to preserve:
- accidents are analyzed from a single consolidated file,
- air is analyzed from a yearly file family (`2016..2023`) and aggregated across years.

Contract with `analysis.json`:
- `analysis.json` is the machine-readable expectation artifact,
- schema is intentionally evolvable (new metrics may be added over time),
- empty sections are valid placeholders until a run populates them.

Execution lifecycle (target state):
1. Run data-shape analysis (metadata first) -> populate `data_shape` in `docs/analysis.json`.
2. Run raw analysis scripts -> populate/update accidents/air metrics in `docs/analysis.json`.
3. Run ETL scripts (unchanged).
4. Run DB-vs-analysis validation using `analysis.json` as expectation source.
5. Record deviations explicitly (counts, reasons, and affected sections).

## Planned Analysis Organization (`scripts/analysis/`)
- Keep analysis scripts separate from ETL scripts; do not mix responsibilities.
- Mirror ETL conceptual split while respecting source asymmetry:
  - `accidents` analysis path (single-file)
  - `air` analysis path (per-year + all-years aggregation)
- Planned script families:
  - runners/orchestrators (single-file and all-years),
  - dimension analyzers,
  - fact analyzers,
  - optional report/validation comparators (analysis vs DB).
- Logging expectations:
  - periodic progress logging (no per-row noise),
  - summarized counters by reason/category,
  - top exception categories for explainability.

## Data Shape We Analyze
- **Accidents source shape**: one consolidated input file
  - `raw/archive/US_Accidents_March23.csv`
- **Air source shape**: yearly file family
  - `raw/daily_aqi_by_county_YYYY.csv`
  - target range for conformed analysis with accidents: `2016..2023`

Goal of this document:
- Define what we analyze in raw data **before touching the database**.
- Make ETL expectations explicit and testable from source-only evidence.
- Keep analysis logic aligned with ETL logic, but as a separate layer (`scripts/analysis/`).

This is an iterative document and may be refined across multiple cycles.

## Accidents - Dimensions
### Purpose
- Understand the raw categorical/time/location shape that drives accident dimensions.
- Quantify expected dimension members and edge cases before loading.
- Discover road-condition boolean parsing config directly from raw columns/values.

### Analysis Targets
- `dim_time`:
  - explicit granularity metadata (`hour`, `YYYYMMDDHH`)
  - expected min/max hourly coverage from raw timestamps
  - expected distinct hour keys at ETL parser rules
  - expected continuous hourly row count across source timestamp range
- `dim_severity`:
  - expected distinct valid severity levels (`>0`)
  - discovered full valid severity-level list from raw data
- `dim_weather_condition`:
  - expected distinct canonical weather categories
  - discovered full canonical weather list as `(weather_condition_nk, weather_condition_name)`
  - expected missing-weather volume (to be mapped to `unknown`)
- `dim_road_condition`:
  - discovered road flag column list from raw schema
  - discovered boolean token profile (`true`/`false` token sets from observed values)
  - expected distinct road-flag combinations using discovered tokens
- `dim_location`:
  - expected detailed members (`D|...`)
  - expected county-level conformed members (`C|county|state|country`)
  - expected unmapped/insufficient location records by reason
  - location-model metrics:
    - row buildability for detail/county keys
    - detail-to-county member ratio
    - county NK set used for cross-source overlap checks

## Accidents - Facts
### Purpose
- Establish expected fact-stage volume and skip profile from raw data under ETL rules.
- Make expected fact completeness and exclusions explainable before DB writes.

### Analysis Targets
- Source grain checks:
  - expected row count and source ID uniqueness profile
- Time validity checks:
  - parseability and ordering (`End_Time >= Start_Time`)
  - timestamp-tail normalization impacts
- Required field validity checks:
  - severity validity
  - coordinate validity/range checks
  - location key buildability (detail + county levels)
- Expected fact outcomes:
  - staged rows
  - skipped rows by reason
  - rows mapped to explicit unknown members (for mandatory FKs)

## Air - Dimensions
### Purpose
- Understand yearly/raw variation in AQI category, defining parameter, and county coverage.
- Establish expected conformed-dimension behavior across all years before loading.
- Discover state-name to state-code mapping from raw records (not from embedded lookup tables).

### Analysis Targets
- Input availability and year coverage:
  - file presence for `2016..2023`
  - per-file row counts and date ranges
- `dim_location` (county-level conformed members):
  - rules-driven `state_name -> state_abbrev` mapping (`scripts/analysis/rules.json`) for ETL-parity county NK construction
  - discovered `state_name -> state_code` profile from raw (`State Code`) for observability/ambiguity diagnostics
  - rules-driven excluded state-name list (from `scripts/analysis/rules.json`)
  - excluded-state row counts per year and all-years (raw evidence for ETL conformance deltas)
  - explicit time-granularity metadata for air daily mapping (`daily -> HH=00`)
  - expected distinct `HH=00` time keys across per-year/all-years files
  - expected `HH=00` overlap with accidents window
  - location-model metrics:
    - row buildability for county keys
    - unbuildable reason profile
    - county NK overlap with accidents county-level members
  - expected county NKs per year
  - expected net-new county NKs across all years
  - expected unknown/unmapped state-name cases
- `dim_aqi_category`:
  - expected distinct canonical category NKs across years
  - expected missing/unknown mapping volume
- `dim_defining_parameter`:
  - expected distinct canonical parameter NKs across years
  - expected missing/unknown mapping volume

## Air - Facts
### Purpose
- Define expected daily county fact volume per year and overall, using ETL-equivalent rules.
- Explain expected skips and conformance constraints before any DB writes.

### Analysis Targets
- Source grain checks:
  - expected uniqueness at (`State Code`, `County Code`, `Date`)
  - expected duplicate/conflict profile if present
- Conformance checks from raw:
  - expected daily `time_key` mapping (`HH=00`)
  - expected county location NK mapping success/failures
- Measure and required-field validity:
  - `AQI >= 0`
  - `Number of Sites Reporting >= 0`
  - date parseability and required-code completeness
- Expected fact outcomes:
  - staged rows per year and total
  - skipped rows per year and total, by reason
  - dominant exception categories (for example, out-of-scope non-US rows)

## Modeling Decisions (Not Discovery)
These rules are design decisions aligned with ETL implementation; they are documented in analysis context but not inferred.

### Time Granularity
- `dim_time` grain is hour-level (`time_key = YYYYMMDDHH`) for both sources.
- Accidents facts preserve exact source timestamps (`start_time`, `end_time`) while joining to hourly `start_time_key` and `end_time_key`.
- Air daily facts map to `time_key` at midnight hour (`HH=00`) for each `source_date`.

### Location Granularity
- `dim_location` is conformed at two levels:
  - Detailed level: `D|street|city|county|state|zipcode|country|timezone`
  - County level: `C|county|state|country`
- Accidents feed both detailed and county members; air feeds county-level members only.
- Fact usage:
  - accidents fact references both detailed and county location keys,
  - air fact references county-level location key.
