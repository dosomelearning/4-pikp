# Pentaho DW Strategy (This Project)

## Goal
Load two data sources into the shared DW model in PostgreSQL:
- US Accidents
- US Air Quality (daily AQI by county)

## Agreed Split

We split ETL by source and by layer:

1. `accidents_dimensions.ktr`
2. `accidents_facts.ktr`
3. `air_dimensions.ktr`
4. `air_facts.ktr`

This is intentional:
- easier debugging (dimension issues isolated from fact issues),
- easier reruns (rebuild facts without reloading all dimensions),
- clearer ownership and scope per source.

## Conformed Dimensions (Cross-Source)

- Shared `dim_time`:
  - accidents use actual hour buckets,
  - air daily rows map to `HH=00` day anchor.
- Shared `dim_location`:
  - accidents keep detailed `location_key`,
  - accidents also populate `county_location_key`,
  - air facts use county-level `location_key`.
- Cross-source join path:
  - `fact_air_quality_daily.location_key = fact_accident.county_location_key`
  - day-level time alignment via shared time key/day.

## Recommended Execution Order

1. Run accidents dimensions
2. Run air dimensions
3. Run accidents facts
4. Run air facts

Reason:
- both fact transformations depend on dimension keys being available.
- location and time conformance must be established before facts.

## Initial Pentaho Artifacts

Workspace location:
- `infra/platform/pentaho`

Transformations:
- `infra/platform/pentaho/transformations/accidents_dimensions.ktr`
- `infra/platform/pentaho/transformations/accidents_facts.ktr`
- `infra/platform/pentaho/transformations/air_dimensions.ktr`
- `infra/platform/pentaho/transformations/air_facts.ktr`

Job:
- `infra/platform/pentaho/jobs/load_dw_all.kjb`

## Implementation Notes

- Current `.ktr/.kjb` are scaffolds to open/edit in WebSpoon.
- Next step in WebSpoon:
  - define DB connection (`dw` PostgreSQL),
  - define CSV inputs,
  - implement SCD2 logic in dimension transformations,
  - implement FK lookup and inserts in fact transformations.

## Current Implemented State

### `accidents_dimensions.ktr` (implemented phase 1)

Implemented and saved directly in file:
- source: `/workspace/raw/archive/US_Accidents_March23.csv` (`CSV file input`)
- embedded DB connection: `dw_pg` (`postgres:5432`, db `dw`)
- working `dim_time` pipeline:
  - `Select Start Time`
  - `Select End Time`
  - `Append Time Streams`
  - `Filter Null Time`
  - `Build Dim Time Fields`
  - `Upsert dim_time`
  - `Discard Null Time`

Derived `dim_time` fields:
- `time_key` (`YYYYMMDDHH`)
- `date_value`
- `year_num`, `month_num`, `day_num`, `hour_num`
- `day_of_week_num`, `day_of_week_name`
- `is_weekend`

Notes:
- this phase only loads `dw.dim_time`.
- remaining accidents dimensions (`dim_location`, `dim_weather_condition`, `dim_road_condition`, `dim_severity`) are still pending in this transformation.
