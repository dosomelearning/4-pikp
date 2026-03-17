# US Air Quality Datasource Profile (Source 2)

## Source
- Dataset: `EPA AQS AirData - Daily AQI by County`
- Primary page: https://aqs.epa.gov/aqsweb/airdata/download_files.html
- Selected file family: `daily_aqi_by_county_YYYY.zip`
- Current local sample used for profiling: `daily_aqi_by_county_2017.csv`

## Scope for This Model
- Use only `daily_aqi_by_county` (no joins with other pollutant datasets).
- Business process: daily county air quality status.
- Fact grain: **one row per county per day**.

## Required Data Elements (Current Scope)
- Measure:
  - `AQI`
  - `Number of Sites Reporting`
- Categorical context:
  - `Category`
  - `Defining Parameter`
- Time/location:
  - `Date`
  - County/state identifiers and names

## Original Source Fields (daily_aqi_by_county)
- `State Name`
- `county Name` (header appears lowercase `c` in sample file)
- `State Code`
- `County Code`
- `Date`
- `AQI`
- `Category`
- `Defining Parameter`
- `Defining Site`
- `Number of Sites Reporting`

## Decision Log

| Decision | Value | Why |
|---|---|---|
| Source scope | `daily_aqi_by_county` only | Avoids forced integration across incompatible grains. |
| Fact grain | County-Day | Matches source dataset exactly. |
| Time dimension | Reuse `dw.dim_time` | Conformed analysis with accidents dataset. |
| Location dimension | Reuse `dw.dim_location` | Shared geographic dimension across sources. |
| Time key mapping | Map daily rows to hour `00` bucket | Reuses shared hourly `dim_time` as day anchor for daily facts. |
| Cross-source join path | Join air facts to accidents via county-level location key | `fact_accident.county_location_key` aligns with county rows used by air facts. |
| Category handling | Separate dimension | Clean low-cardinality descriptive grouping. |
| Defining parameter handling | Separate dimension | Explicit pollutant driver context for each AQI row. |
| Defining site | Keep in fact (degenerate attribute) | Useful traceability without creating extra site dimension now. |

## SCD Options Considered

| Option | Description | Pros | Cons | Decision |
|---|---|---|---|---|
| Type 1 | Overwrite in-place | Simpler ETL | Loses history | Not selected |
| Type 2 | Versioned rows | History preserved | More ETL logic | Selected (project convention for mutable dimensions) |

## Glossary

| Abbreviation | Meaning |
|---|---|
| `nk` | Natural key (business key). |
| `SCD` | Slowly changing dimension. |
| `FK` | Foreign key. |
| `PK` | Primary key. |

## Type 2 Versioning Rule

- One business identifier (`*_nk`) can have multiple version rows.
- Each version row has a different surrogate key (`*_key`).
- `valid_from`/`valid_to` define version validity period.
- `is_current` marks the active version.
- `dim_time` stays static (Type 0).

## Cross-Source Key Semantics (Essential)

- Shared time key behavior:
  - Air facts reuse shared `dw.dim_time.time_key` (`YYYYMMDDHH`).
  - For daily air rows, `HH=00` is used as day anchor.
  - This is the same key space used by accidents time keys.
- Shared location dimension behavior:
  - Air fact uses county-level rows in `dw.dim_location` (`fact_air_quality_daily.location_key`).
  - Accidents fact has two location roles in the same dimension:
    - `location_key` -> detailed accident row
    - `county_location_key` -> county-level conformed row
  - Cross-source joins must use county-level keys:
    - `fact_air_quality_daily.location_key = fact_accident.county_location_key`.

## Source-to-Star Mapping (Planned)

### Legend
- `Original`: copied from source.
- `Derived`: computed/transformed.
- `Logistical`: DW technical field (surrogates/FKs/SCD metadata).

### Planned dimensions

#### `dw.dim_time` (shared, reused)
| Star column | Type | Source field(s) | Mapping / rule |
|---|---|---|---|
| `time_key` | Logistical | `Date` | Existing smart key (`YYYYMMDDHH`); daily rows map to canonical hour bucket (`00` = day anchor at midnight). |
| remaining time attributes | Derived | `Date` | Existing derivation rules reused. |

#### `dw.dim_location` (shared, reused/extended)
| Star column | Type | Source field(s) | Mapping / rule |
|---|---|---|---|
| `location_key` | Logistical | N/A | Existing surrogate key. |
| `location_nk` | Logistical | `Country`, `State Code`, `County Code` | Stable county business key for conformed cross-source joins. |
| `county` | Original | `county Name` | Direct map. |
| `state_code` | Original | `State Code` | Direct map. |
| `country_code` | Derived | N/A | Constant `US` for this source. |
| `valid_from`, `valid_to`, `is_current` | Logistical | N/A | Existing Type 2 semantics reused. |

#### `dw.dim_aqi_category` (new)
| Star column | Type | Source field(s) | Mapping / rule |
|---|---|---|---|
| `aqi_category_key` | Logistical | N/A | Surrogate key. |
| `aqi_category_nk` | Logistical | `Category` | Canonical category token (e.g., `moderate`). |
| `aqi_category_name` | Original | `Category` | Display label from source. |
| `valid_from`, `valid_to`, `is_current` | Logistical | N/A | Type 2 metadata. |

#### `dw.dim_defining_parameter` (new)
| Star column | Type | Source field(s) | Mapping / rule |
|---|---|---|---|
| `defining_parameter_key` | Logistical | N/A | Surrogate key. |
| `defining_parameter_nk` | Logistical | `Defining Parameter` | Canonical parameter token (e.g., `pm2_5`, `ozone`). |
| `defining_parameter_name` | Original | `Defining Parameter` | Display label from source. |
| `valid_from`, `valid_to`, `is_current` | Logistical | N/A | Type 2 metadata. |

### Planned fact table: `dw.fact_air_quality_daily`
| Star column | Type | Source field(s) | Mapping / rule |
|---|---|---|---|
| `time_key` | Logistical | `Date` | FK to shared `dw.dim_time`. |
| `location_key` | Logistical | `State Code`, `County Code` | FK to county-level rows in shared `dw.dim_location`. |
| `aqi_category_key` | Logistical | `Category` | FK to `dw.dim_aqi_category`. |
| `defining_parameter_key` | Logistical | `Defining Parameter` | FK to `dw.dim_defining_parameter`. |
| `aqi` | Original | `AQI` | Daily AQI value. |
| `number_of_sites_reporting` | Original | `Number of Sites Reporting` | Count of sites reporting for row context. |
| `defining_site_code` | Original | `Defining Site` | Degenerate attribute in fact for traceability. |
| `source_state_code` | Original | `State Code` | Optional raw lineage field (if kept in fact). |
| `source_county_code` | Original | `County Code` | Optional raw lineage field (if kept in fact). |
| `source_date` | Original | `Date` | Optional raw lineage field (if kept in fact). |

## Data Behavior Note

For this dataset, missing county-days are expected (not every county reports every day).  
This reflects monitoring/reporting cadence and availability, not necessarily ETL issues.

## Conformed-Dimension Join Note

- `dim_time` is shared with accidents; for air facts, `time_key` represents daily anchor (`HH=00`).
- `dim_location` is shared with accidents; air uses county-level rows.
- Cross-source analysis should join air facts with accidents using:
  - location: `fact_air_quality_daily.location_key = fact_accident.county_location_key`
  - time: day-level alignment (`time_key` day anchor or `date_value`).

## Data Quality Checks to Include
- Ensure uniqueness at source grain: one row per (`State Code`, `County Code`, `Date`).
- Validate `AQI >= 0`.
- Validate `Number of Sites Reporting >= 0`.
- Track unexpected nulls in `Category` or `Defining Parameter`.
- Normalize header inconsistency (`county Name` casing) during ingestion.
