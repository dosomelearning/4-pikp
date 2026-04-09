# US Air Quality Datasource Profile (Source 2, naloga2b)

Primary architecture contract:
- `naloga2b/ARCHITECTURE_DECISIONS.md`

## Source
- Dataset: `EPA AQS AirData - Daily AQI by County`
- Primary page: https://aqs.epa.gov/aqsweb/airdata/download_files.html
- Selected files: `daily_aqi_by_county_YYYY.csv`

## Modeling Intent in `naloga2b`

Air quality is modeled in two parallel fact variants:

- v1 fact (legacy, unchanged): `dw.fact_air_quality_daily`
- v2 fact (new): `dw.fact_air_quality_daily_v2`

Both are valid and intentionally coexist.

## Location Modeling by Version

### v1 (legacy)
- Fact path: `fact_air_quality_daily.location_key -> dim_location.location_key`

### v2 (new snowflake)
- Fact path: `fact_air_quality_daily_v2.county_key -> dim_county.county_key`

This v2 path is explicitly aligned with county-level source grain.

### v2 Natural Keys (Implementation Contract)
- `fact_air_quality_daily_v2` uses source grain as composite natural key and primary key:
  - (`source_state_code`, `source_county_code`, `source_date`)
- `dim_county.county_nk` uses: `C|<county_name>|<state_code>|<country_code>`
- when present, `source_county_code` is retained in `dim_county` for code-based conformance identity.

## Why Keep Both
- Preserve existing v1 ETL and outputs.
- Add new v2 conformance path without rewriting legacy code.
- Compare both approaches with identical source-period data.

## Fact Usage Examples

### v1 county-level analysis via `dim_location`
```sql
SELECT
  dl.state_code,
  dl.county,
  AVG(f.aqi)::numeric(10,2) AS avg_aqi
FROM dw.fact_air_quality_daily f
JOIN dw.dim_location dl
  ON dl.location_key = f.location_key
GROUP BY dl.state_code, dl.county;
```

### v2 county-level analysis via `dim_county`
```sql
SELECT
  dc.state_code,
  dc.county_name,
  AVG(f.aqi)::numeric(10,2) AS avg_aqi
FROM dw.fact_air_quality_daily_v2 f
JOIN dw.dim_county dc
  ON dc.county_key = f.county_key
GROUP BY dc.state_code, dc.county_name;
```

## Data Quality Notes
- Source uniqueness at (`State Code`, `County Code`, `Date`) remains mandatory.
- v2 should prefer code-based county conformance.
- v1 and v2 should be compared with explicit validation checks after load.
