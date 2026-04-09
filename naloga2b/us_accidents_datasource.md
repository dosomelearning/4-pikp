# US-Accidents Datasource Profile (Source 1, naloga2b)

Primary architecture contract:
- `naloga2b/ARCHITECTURE_DECISIONS.md`

## Source
- Dataset: `US-Accidents: A Countrywide Traffic Accident Dataset`
- Primary URL: https://www.kaggle.com/datasets/sobhanmoosavi/us-accidents
- Units convention: keep original US units (`mi`, `F`, `in`, `mph`).

## Modeling Intent in `naloga2b`

Accidents are modeled in two parallel fact variants:

- v1 fact (legacy, unchanged): `dw.fact_accident`
- v2 fact (new): `dw.fact_accident_v2`

Both are valid. They exist side-by-side for clear comparison.

## Location Modeling by Version

### v1 (legacy)
- Dimension path: `dw.dim_location`
- Fact columns:
  - `fact_accident.location_key`
  - `fact_accident.county_location_key`

### v2 (new snowflake)
- Dimensions:
  - `dw.dim_county`
  - `dw.dim_streetcity` (`county_key` FK to `dim_county`)
- Fact columns:
  - `fact_accident_v2.streetcity_key`
  - `fact_accident_v2.county_key`

### v2 Natural Keys (Implementation Contract)
- `dim_county.county_nk` uses: `C|<county_name>|<state_code>|<country_code>`
- `dim_streetcity.streetcity_nk` is a deterministic hash key, not UUID:
  - format: `SC|<sha1_hex>`
  - built from canonical tuple:
    - `<street>|<city>|<zipcode>|<timezone_name>|<county_nk>`
- `fact_accident_v2.source_accident_id` uses source `ID` directly as fact natural key and primary key.

## Why Keep Both
- Preserve and respect invested implementation effort in v1.
- Avoid rewriting stable ETL.
- Allow controlled comparison of query semantics and ETL complexity.

## Fact Usage Examples

### v1 county-based join target
```sql
SELECT
  f.source_accident_id,
  dl.county,
  dl.state_code
FROM dw.fact_accident f
JOIN dw.dim_location dl
  ON dl.location_key = f.county_location_key;
```

### v2 normalized location traversal
```sql
SELECT
  f.source_accident_id,
  ds.city,
  dc.county_name,
  dc.state_code
FROM dw.fact_accident_v2 f
JOIN dw.dim_streetcity ds
  ON ds.streetcity_key = f.streetcity_key
JOIN dw.dim_county dc
  ON dc.county_key = f.county_key;
```

## Data Quality Notes
- v2 county conformance should prefer code-based identification when available.
- county-name alias handling should be explicit in v2 ETL mapping logic.
- v1 and v2 loads should be validated independently and compared.
