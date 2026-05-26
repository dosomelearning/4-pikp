# KPI and Superset Dashboard Plan

This document consolidates the initially proposed BI KPIs from `naloga1/Ekipa12_Predlog_BI.pdf` into the current English project documentation.

## BI Intent

The BI solution studies traffic accidents in the United States through the combined context of accident events, weather conditions, and air quality. The goal is not only to count events, but to understand when, where, and under which environmental conditions accidents are more frequent, more severe, or more operationally demanding.

The original proposal defines these main analytical goals:

- identify relationships between accidents, weather, and air quality;
- count accidents by time unit, location, and other dimensional attributes;
- measure accident handling duration by location and other dimensions;
- measure the share of air-quality observations above defined AQI thresholds;
- support decisions about possible measures for reducing accident volume.

## Assignment Requirements Interpreted for Superset

`naloga6/naloga6.txt` asks for detailed reports and dashboards based on the first assignment proposal. The original tool mentioned there is Power BI Desktop, but the project uses Apache Superset instead. Superset satisfies the same practical requirements for this project:

- data must come directly from the warehouse;
- KPI calculations must be created as explicit measures or SQL expressions;
- each KPI needs one KPI visualization plus at least three additional graphical charts;
- KPI visuals must show the current value, its meaning, trend, and comparison context;
- charts should be varied, visually acceptable, and interactive;
- the dashboard needs at least two user-facing filters;
- at least one chart should support drill-down through a dimension hierarchy.

The already implemented Superset setup gives us the right foundation:

- Superset runs locally at `http://localhost:18088`;
- the `dw` PostgreSQL database is registered in Superset;
- code-driven dataset, chart, and dashboard creation has already been proven by the proof dashboard;
- the completed work for this stretch is BI-layer SQL, virtual datasets, charts, filters, cross-filtering, and dashboard layout, not warehouse redesign.

## Implemented Build Strategy

The dashboard work was built in four controlled phases.

1. Finalize SQL statements for all KPI visualizations.
2. Create each SQL statement as a Superset virtual dataset and inspect it first as a table.
3. Convert validated datasets into graphical Superset charts.
4. Combine charts into interactive KPI dashboards with filters, cross-filtering where useful, and drill/context-menu behavior where Superset supports it cleanly.

This order kept the work testable. If a visual looks wrong, we can first verify whether the issue is the SQL result, the dataset metadata, or the chart configuration.

## Dataset Direction

For the first real dashboard, prefer the v2 warehouse path because it has cleaner county conformance between accidents and air quality:

- accidents: `dw.fact_accident_v2`
- accident location: `dw.dim_county`, `dw.dim_streetcity`
- air quality: `dw.fact_air_quality_daily_v2`
- shared time: `dw.dim_time`

The legacy v1 facts remain useful for comparison, but the first dashboard should avoid mixing v1 and v2 unless the chart explicitly compares the two model paths.

Recommended common dashboard grains:

- accident-only charts: hour, day, month, year, county, state, severity, weather, road condition;
- air-only charts: day, month, year, county, state, AQI category, defining parameter;
- combined accident and AQI charts: state plus month for the first reviewed version; county plus month can be added later if we need finer local comparison.

Potential global filters across all dashboard work:

- date or year/month range;
- state;
- county;
- severity;
- weather condition;
- AQI category, if a later dashboard exposes AQI category as a visible chart dimension;
- defining parameter.

Useful drill-down hierarchy:

- time: year -> month -> day -> hour for accident charts;
- geography: state -> county -> city/street where the chart uses accident v2 detail.

## KPI 1: Accident Count per Time Unit

### Definition

Count the number of accidents in a selected time unit.

### Business Question

How often do accidents occur, and how does accident frequency change across time, location, severity, weather, and road-condition dimensions?

### Formula

```sql
COUNT(*)
```

Primary grouping dimensions:

- time: year, month, day, hour, day of week, weekend flag;
- location: state, county, city, or detailed street/city level depending on dashboard grain;
- accident context: severity, weather condition, road-condition flags.

### Current Warehouse Basis

Preferred fact source for dashboarding:

- `dw.fact_accident_v2` when using the normalized v2 location path;
- `dw.fact_accident` when using the legacy v1 path.

Relevant dimensions:

- `dw.dim_time`
- `dw.dim_county` and `dw.dim_streetcity` for v2
- `dw.dim_location` for v1
- `dw.dim_severity`
- `dw.dim_weather_condition`
- `dw.dim_road_condition`

### Why It Matters

This KPI gives the baseline measure of accident frequency. It supports trend monitoring, comparison across geography and time, and reporting on whether traffic safety appears to improve or deteriorate under selected conditions.

### Proposed Analysis Areas

- PA1: Identify time intervals when accidents are most frequent.
- PA2: Identify time intervals when accidents are most severe.

### Dashboard Implications

Useful Superset views include:

- accident count by hour, day of week, month, and year;
- accident count by state and county;
- accident count split by severity;
- accident count split by weather condition and road-condition attributes.

Recommended chart types:

- time-series line or bar chart for trends;
- heatmap for hour-of-day by day-of-week patterns;
- bar chart for state, county, severity, weather, and road-condition rankings;
- map or geographic table if location granularity is suitable.

### Planned Superset Charts

KPI value chart:

- Chart: total accident count with period comparison.
- Suggested visualization: Big Number with Trendline.
- Meaning indicator: compare the selected period with the previous comparable period; increasing accident count is unfavorable.

Supporting graphical charts:

- Chart 1: accident count trend by month.
  - Suggested visualization: Time-series Line Chart.
  - Purpose: show whether accident frequency is increasing, decreasing, or seasonal.
- Chart 2: accident count heatmap by day of week and hour.
  - Suggested visualization: Heatmap.
  - Purpose: answer PA1 by identifying time intervals with the highest accident frequency.
- Chart 3: accident count by severity over time.
  - Suggested visualization: Stacked Bar Chart or ECharts Timeseries Bar.
  - Purpose: answer PA2 by showing whether severe accidents cluster in specific periods.
- Optional chart 4: top counties by accident count.
  - Suggested visualization: Horizontal Bar Chart.
  - Purpose: show geographic concentration and support state/county filtering.

### SQL Development Targets

Create and validate these SQL result sets first:

- `kpi_accident_count_period`: one row per selected time bucket with accident count and previous-period comparison fields.
- `kpi_accident_count_hour_dow`: accident count grouped by `day_of_week_name` and `hour_num`.
- `kpi_accident_count_severity_time`: accident count grouped by time bucket and `severity_level`.
- `kpi_accident_count_county`: accident count grouped by state and county.

## KPI 2: Accident Handling Duration

### Definition

Measure accident duration between accident start time and end time, usually grouped by time and location. For dashboard visuals, use median and p90 as the primary readable measures because average duration is highly sensitive to extreme records.

### Business Question

Where and under which conditions do accidents take longer to resolve, and can duration be used as a proxy for operational complexity or disruption?

### Formula

```sql
PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY accident_duration_minutes)
PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY accident_duration_minutes)
```

The originally proposed formula was `AVG(endtime - starttime)`. In the current warehouse this derived measure is already stored as `accident_duration_minutes`. Average duration may still be used for secondary analysis, but it is not the primary KPI 2 dashboard encoding.

Primary grouping dimensions:

- time: year, month, day, hour, day of week, weekend flag;
- location: state, county, city, or detailed street/city level;
- accident context: severity, weather condition, road-condition flags.

### Current Warehouse Basis

Preferred fact source for dashboarding:

- `dw.fact_accident_v2.accident_duration_minutes` when using the normalized v2 location path;
- `dw.fact_accident.accident_duration_minutes` when using the legacy v1 path.

Relevant dimensions:

- `dw.dim_time`
- `dw.dim_county` and `dw.dim_streetcity` for v2
- `dw.dim_location` for v1
- `dw.dim_severity`
- `dw.dim_weather_condition`
- `dw.dim_road_condition`

### Why It Matters

Accident duration helps approximate the operational burden of an accident. Longer durations can indicate more complex incidents, more severe disruptions, worse environmental conditions, or location-specific response constraints.

### Proposed Analysis Areas

- PA3: Analyze how accident duration depends on selected dimensions.
- PA4: Analyze how accident duration relates to weather phenomena.

### Dashboard Implications

Useful Superset views include:

- median and p90 accident duration over time;
- median duration by state and county;
- median duration by severity;
- median duration by weather condition;
- median duration by selected road-condition flags;
- accident count by county for volume context.

Recommended chart types:

- time-series line chart for duration trends;
- box plot or percentile-oriented chart if Superset dataset preparation exposes distribution metrics;
- bar chart for highest-duration locations, weather conditions, or severity levels;
- ranking chart for accident count by county.

### Planned Superset Charts

KPI value chart:

- Chart: median accident duration with trend.
- Suggested visualization: Big Number with Trendline.
- Meaning indicator: compare selected-period median duration with the previous period; increasing duration is unfavorable because it suggests more disruption or handling complexity.

Supporting graphical charts:

- Chart 1: median and p90 duration by month.
  - Suggested visualization: Time-series Line Chart.
  - Purpose: show trend and seasonality in accident handling duration.
- Chart 2: median duration by weather condition.
  - Suggested visualization: Horizontal Bar Chart.
  - Purpose: answer PA4 by showing which weather conditions are associated with longer incidents.
- Chart 3: median duration by severity and road-condition signal.
  - Suggested visualization: Grouped Bar Chart or Pivot Table converted to a heatmap-style visual if supported cleanly.
  - Purpose: answer PA3 by comparing duration across accident dimensions.
- Chart 4: top counties by accident count.
  - Suggested visualization: Horizontal Bar Chart.
  - Purpose: show county volume context without the broken row-level scatter scale.

### SQL Development Targets

Create and validate these SQL result sets first:

- `kpi_accident_duration_period`: one row per accident with filter dimensions so Superset can calculate median and p90 by time.
- `kpi_accident_duration_weather`: one row per accident with weather and filter dimensions so Superset can calculate median duration by weather.
- `kpi_accident_duration_severity_road`: one row per accident with severity, road signal, and filter dimensions so Superset can calculate median duration.
- `kpi_accident_count_duration_county`: one row per accident with county and filter dimensions so Superset can calculate county accident counts.

## KPI 3: Share of Bad-Air AQI Days

### Definition

Measure the share of daily air-quality observations where AQI indicates bad air. The original proposal defines bad air as `AQI > 100`.

### Business Question

How often does air quality exceed the bad-air threshold, and does this pattern align with accident frequency, severity, or duration across time and geography?

### Formula

```sql
COUNT(*) FILTER (WHERE aqi > 100)::numeric / NULLIF(COUNT(*), 0)
```

Equivalent percentage:

```sql
100.0 * COUNT(*) FILTER (WHERE aqi > 100) / NULLIF(COUNT(*), 0)
```

Primary grouping dimensions:

- time: date, month, year;
- location: state and county;
- air-quality context: defining parameter. AQI category remains a possible later extension, but the implemented dashboards use the fixed `AQI > 100` threshold.

### Current Warehouse Basis

Preferred fact source for dashboarding:

- `dw.fact_air_quality_daily_v2` when using the normalized v2 county path;
- `dw.fact_air_quality_daily` when using the legacy v1 path.

Relevant dimensions:

- `dw.dim_time`
- `dw.dim_county` for v2
- `dw.dim_location` for v1
- `dw.dim_aqi_category`
- `dw.dim_defining_parameter`

### Why It Matters

Lower AQI values represent better air quality. Values above 100 indicate air that is unhealthy for sensitive groups or worse, depending on the AQI category. This KPI supports the project goal of exploring whether degraded air quality has a visible relationship with accident patterns.

### Proposed Analysis Areas

- PA5: Identify environmental extremes.
- PA6: Identify trends in environmental conditions over time.

### Dashboard Implications

Useful Superset views include:

- bad-air day share by month and year;
- bad-air day share by state and county;
- bad-air observations by defining parameter;
- comparison of bad-air share with accident count, severity, or duration at county/date or county/month grain.

Recommended chart types:

- time-series line chart for AQI bad-air share;
- bar chart for counties or states with highest bad-air share;
- table with defining parameter, total observations, bad-air observations, and percentage;
- combined dashboard slice comparing air-quality KPI movement with accident KPIs.

### Planned Superset Charts

KPI value chart:

- Chart: percentage of bad-air AQI observations.
- Suggested visualization: Gauge or Big Number with Trendline.
- Meaning indicator: `AQI > 100` is unfavorable; lower percentages are better.

Supporting graphical charts:

- Chart 1: bad-air share by month.
  - Suggested visualization: Time-series Line Chart.
  - Purpose: answer PA6 by showing movement in air-quality conditions over time.
- Chart 2: bad-air share by state or county.
  - Suggested visualization: Horizontal Bar Chart.
  - Purpose: show locations with the highest share of bad-air observations.
- Chart 3: bad-air share by defining parameter.
  - Suggested visualization: Bar Chart or Treemap.
  - Purpose: identify which pollutant parameter most often defines unhealthy AQI days.
- Optional chart 4: accident count and bad-air share by month.
  - Suggested visualization: Mixed Time-series Chart.
  - Purpose: compare KPI 3 with KPI 1 at a common time grain.

### SQL Development Targets

Create and validate these SQL result sets first:

- `kpi_aqi_bad_air_period`: total AQI observations, bad-air observations, and bad-air percentage by time bucket.
- `kpi_aqi_bad_air_county`: bad-air percentage grouped by state and county.
- `kpi_aqi_bad_air_parameter`: bad-air percentage grouped by defining parameter.
- `kpi_accidents_vs_aqi_monthly`: accident count, average accident duration, average AQI, and bad-air percentage by state and month.

## Superset Planning Alignment

Superset is already integrated as the dashboarding layer and can reach the PostgreSQL warehouse through the registered `dw` database. The proof dashboard has already validated that virtual datasets, charts, and dashboards can be provisioned from code.

The implemented dashboard work focuses on BI-layer virtual datasets and chart SQL rather than warehouse redesign. Based on `docs/superset.md` and `docs/superset_handoff.md`, the dashboards:

- use the registered `dw` connection in Superset;
- create KPI-oriented virtual datasets or database views with user-friendly columns;
- support filters for time, state, county, severity, weather, road signal, and defining parameter where those dimensions appear in visible dashboard charts;
- use the v2 fact path for the implemented dashboard datasets;
- start with the three KPI dashboards and add a fourth relationship dashboard for accidents and air quality.

Implemented dashboard structure:

- Dashboard 3: KPI 1 accident frequency across time, location, and severity.
- Dashboard 4: KPI 2 accident duration across time, location, severity, weather, and road signal.
- Dashboard 5: KPI 3 bad-air AQI share across time, location, and defining parameter.
- Dashboard 6: accident and air-quality relationship analysis at state/month grain.

## Implementation Sequence and Status

### Milestone Status

Current status after implementation:

- Milestone 1: complete. Local SQL statements are recorded under `naloga6/sql/` and validated by `./scripts/run-kpi-sql.sh`.
- Milestone 2: complete. The same SQL statements are copied into Superset, executed through the Superset warehouse connection, and previewed as table charts.
- Milestone 3: complete. Superset virtual datasets are created from the validated SQL statements.
- Milestone 5: complete. Graphical Superset charts are created from those datasets.
- Dashboard milestone KPI 1: complete. `KPI 1 - Accident Frequency Dashboard` is created in Superset.
- Dashboard milestone KPI 2: complete. `KPI 2 - Accident Duration Dashboard` is created in Superset.
- Dashboard milestone KPI 3: complete. `KPI 3 - Air Quality Dashboard` is created in Superset.
- Dashboard 4 asset milestone: complete. Correlation SQL, SQL previews, datasets, and charts are created.
- Dashboard milestone 4: complete. `Dashboard 4 - Accidents and Air Quality Relationship` is created in Superset.

Dashboard assembly and first-pass interactions are complete for all four dashboards. Dashboard-native filters and cross-filtering are configured only for dimensions that appear in the visible dashboard charts.

### Step 1: SQL Workspace

Create a dedicated SQL workspace for dashboard query drafts:

- `naloga6/sql/`

Each SQL file holds one chart-oriented result set. We run each query against PostgreSQL first, then use the validated query in Superset as a virtual dataset.

Reproducible local validation command:

```bash
./scripts/run-kpi-sql.sh
```

Run one query file only:

```bash
./scripts/run-kpi-sql.sh naloga6/sql/01_kpi_accident_count_period.sql
```

The runner:

- reads `infra/compose/.env`;
- executes SQL inside the PostgreSQL container through Docker Compose;
- stops on the first SQL error;
- prints each result set in `psql`;
- prints elapsed seconds per SQL file.

Validation result:

- `./scripts/run-kpi-sql.sh` completed with `RESULT: OK`.
- Validated fact row baseline:
  - `dw.fact_accident_v2`: `7,728,394` rows.
  - `dw.fact_air_quality_daily_v2`: `2,599,493` rows.

### SQL Catalog

The following SQL files are the current local source of truth for KPI chart result sets.

| File | KPI | Purpose | Grain | Intended Superset visualization |
| --- | --- | --- | --- | --- |
| `naloga6/sql/01_kpi_accident_count_period.sql` | KPI 1 | Monthly accident count with previous-month comparison | one row per accident start month | Big Number with Trendline; line chart |
| `naloga6/sql/02_kpi_accident_count_hour_dow.sql` | KPI 1 | Accident frequency by weekday and hour | day-of-week plus hour | heatmap |
| `naloga6/sql/03_kpi_accident_count_severity_time.sql` | KPI 1 | Accident frequency by severity over time | month plus severity level | stacked bar chart |
| `naloga6/sql/04_kpi_accident_count_county.sql` | KPI 1 | County accident concentration | state plus county | horizontal bar chart |
| `naloga6/sql/05_kpi_accident_duration_period.sql` | KPI 2 | Accident duration base rows for median and p90 over time | one row per accident | Big Number with Trendline; line chart |
| `naloga6/sql/06_kpi_accident_duration_weather.sql` | KPI 2 | Duration by weather condition with filter dimensions | one row per accident | horizontal bar chart |
| `naloga6/sql/07_kpi_accident_duration_severity_road.sql` | KPI 2 | Duration by severity and primary road signal with filter dimensions | one row per accident | grouped bar chart |
| `naloga6/sql/08_kpi_accident_count_duration_county.sql` | KPI 2 | County accident count base rows with duration context | one row per accident | horizontal bar chart |
| `naloga6/sql/09_kpi_aqi_bad_air_period.sql` | KPI 3 | Bad-air share base rows with weighted chart metrics | observation date plus state/county/parameter | Big Number with Trendline; line chart |
| `naloga6/sql/10_kpi_aqi_bad_air_county.sql` | KPI 3 | Bad-air share by county with filter dimensions | observation date plus state/county/parameter | horizontal bar chart |
| `naloga6/sql/11_kpi_aqi_bad_air_parameter.sql` | KPI 3 | Bad-air contribution by defining parameter with filter dimensions | observation date plus state/county/parameter | donut chart |
| `naloga6/sql/12_kpi_accidents_vs_aqi_monthly.sql` | Combined | Accident count, duration, and AQI at common grain | state plus month | mixed time-series chart or scatter plot |
| `naloga6/sql/13_kpi_accidents_aqi_state_month_correlation_base.sql` | Dashboard 4 | Base accident and AQI measures for relationship analysis | state plus month | scatter charts and mixed time-series chart |
| `naloga6/sql/14_kpi_accidents_aqi_correlation_summary.sql` | Dashboard 4 | Overall accident/AQI correlation coefficients | one summary row | Big Number correlation cards |
| `naloga6/sql/15_kpi_accidents_aqi_state_correlation.sql` | Dashboard 4 | Per-state accident/AQI correlation coefficients | state | state ranking bar chart |

Shared SQL decisions:

- use the v2 fact path for the main dashboard;
- use `AQI > 100` as the bad-air threshold from the original proposal;
- treat `severity_level = 4` as the severe-accident indicator for initial PA2 analysis;
- use monthly grain for trend/KPI comparison charts because it is readable and works across both accident and AQI facts;
- use state plus month as the first combined comparison grain between accidents and AQI because it is readable in direct SQL validation and still supports dashboard filtering;
- apply `HAVING` thresholds and `LIMIT` clauses only on ranking-style result sets to keep first-pass charts readable.

### Step 2: Superset Table Inspection

For each finalized SQL statement:

- create or update a Superset virtual dataset;
- create a temporary table chart or use Explore table view;
- verify row counts, grouping grain, null handling, sorting, and labels;
- only then convert the same dataset into the intended graphical chart.

Reproducible Superset asset command:

```bash
./scripts/superset-create-kpi-assets.sh
```

The script:

- reads SQL from `naloga6/sql/`;
- copies the SQL files into the Superset container under `/tmp/pikp_kpi_sql`;
- creates or updates Superset virtual datasets;
- runs a `LIMIT 5` preview query through Superset's registered `dw` database for every SQL statement;
- creates one table-preview chart per SQL statement;
- creates the graphical KPI charts.

Superset table-preview charts:

| SQL file | Superset table-preview chart |
| --- | --- |
| `01_kpi_accident_count_period.sql` | `KPI SQL Preview - 01_kpi_accident_count_period` |
| `02_kpi_accident_count_hour_dow.sql` | `KPI SQL Preview - 02_kpi_accident_count_hour_dow` |
| `03_kpi_accident_count_severity_time.sql` | `KPI SQL Preview - 03_kpi_accident_count_severity_time` |
| `04_kpi_accident_count_county.sql` | `KPI SQL Preview - 04_kpi_accident_count_county` |
| `05_kpi_accident_duration_period.sql` | `KPI SQL Preview - 05_kpi_accident_duration_period` |
| `06_kpi_accident_duration_weather.sql` | `KPI SQL Preview - 06_kpi_accident_duration_weather` |
| `07_kpi_accident_duration_severity_road.sql` | `KPI SQL Preview - 07_kpi_accident_duration_severity_road` |
| `08_kpi_accident_count_duration_county.sql` | `KPI SQL Preview - 08_kpi_accident_count_duration_county` |
| `09_kpi_aqi_bad_air_period.sql` | `KPI SQL Preview - 09_kpi_aqi_bad_air_period` |
| `10_kpi_aqi_bad_air_county.sql` | `KPI SQL Preview - 10_kpi_aqi_bad_air_county` |
| `11_kpi_aqi_bad_air_parameter.sql` | `KPI SQL Preview - 11_kpi_aqi_bad_air_parameter` |
| `12_kpi_accidents_vs_aqi_monthly.sql` | `KPI SQL Preview - 12_kpi_accidents_vs_aqi_monthly` |
| `13_kpi_accidents_aqi_state_month_correlation_base.sql` | `KPI SQL Preview - 13_kpi_accidents_aqi_state_month_correlation_base` |
| `14_kpi_accidents_aqi_correlation_summary.sql` | `KPI SQL Preview - 14_kpi_accidents_aqi_correlation_summary` |
| `15_kpi_accidents_aqi_state_correlation.sql` | `KPI SQL Preview - 15_kpi_accidents_aqi_state_correlation` |

### Step 3: Chart Automation

The implementation follows the proven pattern from `scripts/superset-create-proof-dashboard.sh`. The KPI automation scripts are idempotent and create or update:

- KPI virtual datasets;
- KPI value charts;
- supporting graphical charts;
- dashboard layouts;
- native filters for time, state, county, severity, weather, road signal, and defining parameter where appropriate.

Implemented asset script:

- `scripts/superset-create-kpi-assets.sh`

Implemented dashboard script:

- `scripts/superset-create-kpi-dashboard.sh <kpi1|kpi2|kpi3|kpi4>`

The asset script creates datasets and charts. The dashboard script creates the published dashboards, layout, native filters, and cross-filter configuration.

### Superset Virtual Datasets

| Dataset | Source SQL |
| --- | --- |
| `kpi_kpi_accident_count_period` | `01_kpi_accident_count_period.sql` |
| `kpi_kpi_accident_count_hour_dow` | `02_kpi_accident_count_hour_dow.sql` |
| `kpi_kpi_accident_count_severity_time` | `03_kpi_accident_count_severity_time.sql` |
| `kpi_kpi_accident_count_county` | `04_kpi_accident_count_county.sql` |
| `kpi_kpi_accident_duration_period` | `05_kpi_accident_duration_period.sql` |
| `kpi_kpi_accident_duration_weather` | `06_kpi_accident_duration_weather.sql` |
| `kpi_kpi_accident_duration_severity_road` | `07_kpi_accident_duration_severity_road.sql` |
| `kpi_kpi_accident_count_duration_county` | `08_kpi_accident_count_duration_county.sql` |
| `kpi_kpi_aqi_bad_air_period` | `09_kpi_aqi_bad_air_period.sql` |
| `kpi_kpi_aqi_bad_air_county` | `10_kpi_aqi_bad_air_county.sql` |
| `kpi_kpi_aqi_bad_air_parameter` | `11_kpi_aqi_bad_air_parameter.sql` |
| `kpi_kpi_accidents_vs_aqi_monthly` | `12_kpi_accidents_vs_aqi_monthly.sql` |
| `kpi_kpi_accidents_aqi_state_month_correlation_base` | `13_kpi_accidents_aqi_state_month_correlation_base.sql` |
| `kpi_kpi_accidents_aqi_correlation_summary` | `14_kpi_accidents_aqi_correlation_summary.sql` |
| `kpi_kpi_accidents_aqi_state_correlation` | `15_kpi_accidents_aqi_state_correlation.sql` |

### Superset Graphical Charts

| Chart | Superset viz type | Purpose |
| --- | --- | --- |
| `KPI - KPI1 Accident Count` | `big_number` | KPI 1 current value and trend |
| `KPI - KPI1 Accident Count Trend` | `echarts_timeseries_line` | monthly accident trend |
| `KPI - KPI1 Accidents by Weekday and Hour` | `echarts_timeseries_bar` | weekday/hour accident pattern |
| `KPI - KPI1 Accidents by Severity Over Time` | `echarts_timeseries_bar` | severity trend over time |
| `KPI - KPI1 Top Counties by Accident Count` | `echarts_timeseries_bar` | county concentration |
| `KPI - KPI2 Median Accident Duration` | `big_number` | KPI 2 current value and trend |
| `KPI - KPI2 Duration Trend` | `echarts_timeseries_line` | median and p90 duration trend |
| `KPI - KPI2 Duration by Weather` | `echarts_timeseries_bar` | weather-duration relationship |
| `KPI - KPI2 Duration by Severity and Road Signal` | `echarts_timeseries_bar` | severity and road-context duration comparison |
| `KPI - KPI2 Top Counties by Accident Count` | `echarts_timeseries_bar` | county accident-volume ranking |
| `KPI - KPI3 Bad-Air AQI Share` | `big_number` | KPI 3 current value and trend |
| `KPI - KPI3 Bad-Air Share Trend` | `echarts_timeseries_line` | bad-air share and average AQI trend |
| `KPI - KPI3 Counties by Bad-Air Share` | `echarts_timeseries_bar` | county bad-air concentration |
| `KPI - KPI3 Bad-Air by Defining Parameter` | `pie` | pollutant contribution to bad-air observations |
| `KPI - Combined Accidents and AQI by Month` | `mixed_timeseries` | accident volume and bad-air share comparison |
| `KPI - AQI Accident Count Correlation` | `big_number_total` | overall correlation between accident count and bad-air share |
| `KPI - AQI Duration Correlation` | `big_number_total` | overall correlation between average accident duration and bad-air share |
| `KPI - AQI Severity Correlation` | `big_number_total` | overall correlation between severe accident share and bad-air share |
| `KPI - AQI vs Accident Count Scatter` | `echarts_timeseries_scatter` | state/month bad-air share versus accident count |
| `KPI - AQI vs Duration Scatter` | `echarts_timeseries_scatter` | state/month bad-air share versus average accident duration |
| `KPI - State AQI Accident Correlation Ranking` | `echarts_timeseries_bar` | per-state accident-count correlation ranking |
| `KPI - Accidents and AQI Monthly Comparison` | `mixed_timeseries` | accident volume and bad-air share comparison using the correlation base dataset |

Chart implementation decisions:

- Superset's MCP chart helper supports a smaller semantic chart set (`big_number`, `xy`, `mixed_timeseries`, `pie`, `pivot_table`, `table`) and maps those to concrete Superset viz types.
- The originally planned heatmap is represented for now as a grouped bar chart for weekday/hour accident patterns. This keeps the chart graphical and generated through supported Superset automation.
- The AQI defining-parameter chart uses a donut/pie chart because the source has a small categorical parameter set and the assignment asks for varied graphical visuals.
- The combined accident/AQI chart uses a mixed time-series chart with accident count on the primary axis and bad-air percentage on the secondary axis.

### Step 4: Dashboard Assembly

The implemented dashboard set is visually simple and analysis-first:

- KPI 1 dashboard: accident frequency visuals.
- KPI 2 dashboard: accident duration visuals.
- KPI 3 dashboard: air-quality visuals.
- Dashboard 4: combined accident and AQI relationship visuals.

Implemented interactions include:

- dashboard-level filters;
- chart-level cross-filtering where Superset supports it cleanly;
- drill/context-menu behavior on compatible visible charts;
- consistent color semantics, where unfavorable values trend toward red/orange and favorable values trend toward green/blue.

Implemented dashboard composition script:

```bash
./scripts/superset-create-kpi-dashboard.sh <kpi1|kpi2|kpi3|kpi4>
```

The script creates or updates exactly one KPI dashboard per run. This lets us pause after each dashboard milestone and inspect layout before proceeding.

### KPI 1 Dashboard

Reproducible command:

```bash
./scripts/superset-create-kpi-dashboard.sh kpi1
```

Superset dashboard:

- Title: `KPI 1 - Accident Frequency Dashboard`
- URL: `http://localhost:18088/superset/dashboard/3/`
- Status: created and published.

Layout:

- Row 1:
  - `KPI - KPI1 Accident Count`
  - `KPI - KPI1 Accident Count Trend`
- Row 2:
  - `KPI - KPI1 Accidents by Weekday and Hour`
- Row 3:
  - `KPI - KPI1 Accidents by Severity Over Time`
  - `KPI - KPI1 Top Counties by Accident Count`

Current interaction status:

- Native dashboard filters are configured.
- Cross-filtering is enabled.
- Drill-down/context-menu interaction is available on compatible visible charts.

### KPI 1 Filter and Drill-Down Proposal

General dashboard interaction rule:

- Add filtering and interaction only for charts that are visible on the dashboard.
- Do not add dashboard filters for dimensions that are not represented by visible charts on that dashboard.
- When a visible dashboard filter is semantically relevant to a visible chart, the chart should recompute from the filtered data rather than keep showing a fixed all-time aggregate.
- Count-based charts must preserve the filter dimensions needed by the dashboard and let Superset perform the final visual aggregation.
- Leave outliers visible as they are. Outlier investigation, capping, filtering, or exclusion is intentionally out of scope for the current interaction work.

For `KPI 1 - Accident Frequency Dashboard`, the visible charts are:

- `KPI - KPI1 Accident Count`
- `KPI - KPI1 Accident Count Trend`
- `KPI - KPI1 Accidents by Weekday and Hour`
- `KPI - KPI1 Accidents by Severity Over Time`
- `KPI - KPI1 Top Counties by Accident Count`

Initial native filter plan:

- Time range:
  - Applies to the accident-count KPI card, monthly trend, weekday/hour chart, severity-over-time chart, and county ranking where compatible.
  - Supports the main KPI question of how accident frequency changes over the selected reporting period.
- State:
  - Applies to the county ranking and any other KPI 1 chart dataset that exposes state.
  - Serves as the primary geographic filter before county-level analysis.
- County:
  - Applies to the county ranking and any other KPI 1 chart dataset that exposes county.
  - Should be scoped only to compatible charts so it does not break charts without county columns.
- Severity:
  - Applies to the severity-over-time chart and any other KPI 1 chart dataset that exposes severity.
  - Supports focused analysis of high-severity or lower-severity accident frequency.

Weather condition is not proposed for KPI 1 at this stage because the current KPI 1 dashboard does not include a visible weather-condition chart.

Initial cross-filtering plan:

- Enable cross-filtering on the severity chart if it can filter compatible charts by `severity_level`.
- Enable cross-filtering on the county ranking if it can filter compatible charts by state and county.
- Enable time-based cross-filtering from the trend chart only if Superset emits a clear and predictable time filter for compatible charts.

Initial drill-down plan:

- Primary drill-down path: time hierarchy, `year -> month -> day -> hour`.
- Preferred target chart: `KPI - KPI1 Accident Count Trend`.
- If native drill-down cannot be configured cleanly on the existing trend chart, add one dedicated visible KPI 1 drill-down chart backed by explicit time hierarchy columns.
- Do not add hidden helper charts solely for interaction behavior.

Implemented KPI 1 interaction status:

- Dashboard rebuilt by running:

```bash
./scripts/superset-create-kpi-assets.sh
./scripts/superset-create-kpi-dashboard.sh kpi1
```

- Native filters added:
  - `Time range`: scoped to all five visible KPI 1 charts.
  - `State`: scoped to all five visible KPI 1 charts.
  - `County`: scoped to all five visible KPI 1 charts, cascaded under `State`.
  - `Severity`: scoped to all five visible KPI 1 charts.
- Cross-filtering enabled:
  - `KPI - KPI1 Accidents by Severity Over Time` emits filters to all five visible KPI 1 charts.
  - `KPI - KPI1 Top Counties by Accident Count` emits filters to all five visible KPI 1 charts.
- SQL support added for interactive filters:
  - `01_kpi_accident_count_period.sql` now preserves `accident_date`, `state_code`, `county_name`, and `severity_level`.
  - `02_kpi_accident_count_hour_dow.sql` now preserves `accident_date`, `state_code`, `county_name`, and `severity_level`.
  - `03_kpi_accident_count_severity_time.sql` now preserves `accident_date`, `state_code`, `county_name`, and `severity_level`.
  - `04_kpi_accident_count_county.sql` now preserves `accident_date`, `state_code`, `county_name`, and `severity_level`.
  - Internal SQL `ORDER BY`, `HAVING`, and `LIMIT` clauses were removed from KPI 1 virtual datasets where they could make filtered dashboard results pre-sorted or pre-limited before user interaction.
- No weather filter was added because KPI 1 has no visible weather-condition chart.
- No outlier filtering or value capping was added.

### KPI 1 Chart Reading Guide

General reading notes:

- All KPI 1 charts should be interpreted in the current dashboard filter context.
- Active filters are selected in the dashboard filter bar: `Time range`, `State`, `County`, and `Severity`.
- Superset displays filter indicators on charts to show that a chart is affected by dashboard filters.
- For `KPI - KPI1 Accidents by Weekday and Hour` and `KPI - KPI1 Top Counties by Accident Count`, Superset may show only one active filter indicator even when the inline SQL query includes multiple active filters. This appears to be a Superset filter-badge display issue. The chart SQL should be treated as the source of truth for whether filters are applied.
- No outliers are removed or capped in KPI 1.

`KPI - KPI1 Accident Count`:

- Chart type: Big Number with Trendline.
- Big number: the accident count for the latest visible time bucket in the selected filter context.
- Trendline: accident count over time, grouped by month.
- Hover values on the trendline: accident count for the hovered month.
- Smaller percentage value: change from the latest visible monthly bucket to the previous monthly bucket.
- Important interpretation note: the big number is not the total accident count for the entire selected time range. It is the latest bucket value shown by Superset's Big Number with Trendline visualization.

`KPI - KPI1 Accident Count Trend`:

- Chart type: monthly time-series line chart.
- Each point represents the accident count for one month after the active dashboard filters are applied.
- Use this chart to read the overall accident-frequency trend across the selected time range.
- A higher point means more accidents in that month within the selected state, county, and severity context.

`KPI - KPI1 Accidents by Weekday and Hour`:

- Chart type: grouped bar chart using hour of day on the x-axis and weekday as the series.
- Each bar segment represents accident count for a weekday/hour combination after active dashboard filters are applied.
- Use this chart to identify recurring temporal patterns, such as whether filtered accidents cluster around commute hours or particular weekdays.
- If `Time range` is changed, this chart should represent only accidents within that selected date range even if Superset's visible filter badge does not list every active filter.

`KPI - KPI1 Accidents by Severity Over Time`:

- Chart type: stacked monthly bar chart.
- Each monthly bar represents accident count after active dashboard filters are applied.
- Bar segments split the monthly accident count by `severity_level`.
- Use this chart to compare whether selected accident volume is mostly lower-severity or higher-severity over time.
- Selecting a severity filter should reduce the visible series to the selected severity context.

`KPI - KPI1 Top Counties by Accident Count`:

- Chart type: horizontal bar chart.
- Each bar represents accident count for a county after active dashboard filters are applied.
- State is used as a grouping/series dimension.
- Use this chart to identify where accidents are concentrated geographically in the selected time and severity context.
- Applying a state or county filter narrows the county ranking to that selected geography. If a single county is selected, the chart may collapse to that county because the ranking has only one selected county left.
- If Superset's visible filter badge lists fewer filters than are active, inspect the inline SQL query; the SQL should include the active `Time range`, `State`, `County`, and `Severity` filters.

Manual testing checklist:

- Open `http://localhost:18088/superset/dashboard/3/`.
- Confirm the filter bar shows `Time range`, `State`, `County`, and `Severity`.
- Apply a `Severity` value and confirm all five visible KPI 1 charts update.
- Apply `State` and then `County`; confirm all five visible KPI 1 charts update.
- Apply `Time range`; confirm all five visible KPI 1 charts update, including `KPI - KPI1 Accidents by Weekday and Hour`.
- Click or context-click values in the severity and county charts to test Superset cross-filter and drill/context-menu behavior.

### KPI 2 Dashboard

Reproducible command:

```bash
./scripts/superset-create-kpi-dashboard.sh kpi2
```

Superset dashboard:

- Title: `KPI 2 - Accident Duration Dashboard`
- URL: `http://localhost:18088/superset/dashboard/4/`
- Status: created and published.

Layout:

- Row 1:
  - `KPI - KPI2 Median Accident Duration`
  - `KPI - KPI2 Duration Trend`
- Row 2:
  - `KPI - KPI2 Duration by Weather`
  - `KPI - KPI2 Duration by Severity and Road Signal`
- Row 3:
  - `KPI - KPI2 Top Counties by Accident Count`

Current interaction status:

- Native dashboard filters are configured.
- Cross-filtering is enabled.
- Visible dashboard filters:
  - `Time range`: scoped to all five visible KPI 2 charts through `accident_date`.
  - `State`: scoped to all five visible KPI 2 charts through `state_code`.
  - `County`: scoped to all five visible KPI 2 charts through `county_name`.
  - `Severity`: scoped to all five visible KPI 2 charts through `severity_level`.
  - `Weather condition`: scoped to all five visible KPI 2 charts through `weather_condition_name`.
  - `Primary road signal`: scoped to all five visible KPI 2 charts through `primary_road_signal`.
- Cross-filtering emitters:
  - `KPI - KPI2 Duration by Weather`
  - `KPI - KPI2 Duration by Severity and Road Signal`
  - `KPI - KPI2 Top Counties by Accident Count`
- KPI 2 SQL datasets now preserve filter dimensions and let Superset calculate chart metrics in the active dashboard filter context.
- Outliers are intentionally left in the data. No duration capping, trimming, or exclusion is applied.

Polish notes from visual inspection:

- The duration charts use median and p90 instead of average-first encoding so extreme duration records do not flatten the visible chart scale.
- The weather duration chart is limited to the top 15 displayed weather labels for readability. The `Weather condition` filter can still inspect other values.
- The county scatter was replaced because row-level accident count made every point land at `1`. County volume is now shown as a top-county accident-count ranking.

### KPI 2 Chart Reading Guide

General interpretation:

- All visible KPI 2 charts should be interpreted in the current filter context.
- Active filters are `Time range`, `State`, `County`, `Severity`, `Weather condition`, and `Primary road signal`.
- The KPI 2 source datasets are one row per accident. Averages, counts, medians, and percentiles are calculated by Superset after dashboard filters are applied.
- `primary_road_signal` is a derived road-condition label that chooses the most prominent available road flag for the accident.
- No outliers are removed or capped.

`KPI - KPI2 Median Accident Duration`:

- Chart type: Big Number with Trendline.
- The large number is the latest monthly median accident duration in minutes within the active filter context.
- The line shows monthly median accident duration across the selected time range.
- Hover values on the line are monthly medians, so they may differ from the large number.
- The percentage under the large number compares the latest displayed month with the previous displayed month.

`KPI - KPI2 Duration Trend`:

- Chart type: monthly line chart.
- The chart shows median and p90 accident duration in minutes for each month after active filters are applied.
- Median helps show the typical accident duration when extreme durations distort the average.
- P90 shows the upper tail: 90 percent of selected accidents are at or below this duration.

`KPI - KPI2 Duration by Weather`:

- Chart type: horizontal bar chart.
- Each bar shows median accident duration in minutes for a weather condition after active filters are applied.
- The chart displays the top 15 weather-condition rows for readability.
- Use this chart to compare which weather labels are associated with longer or shorter selected accident durations.
- Selecting a weather condition narrows the rest of the dashboard to that weather context.

`KPI - KPI2 Duration by Severity and Road Signal`:

- Chart type: grouped bar chart.
- Each bar shows median accident duration in minutes for a derived road signal.
- Bar grouping splits the values by `severity_level`.
- Use this chart to compare whether selected road signals and severity levels are associated with longer accident durations.
- Selecting a road signal or severity value filters the rest of the KPI 2 dashboard.

`KPI - KPI2 Top Counties by Accident Count`:

- Chart type: horizontal bar chart.
- Each bar shows accident count for a county after active filters are applied.
- State is used as a grouping/series dimension.
- Use this chart to identify the highest-volume counties in the selected time, severity, weather, and road-signal context.
- Applying state or county filters narrows the ranking to the selected geography. Selecting a single county may collapse the chart to that county.

### KPI 3 Dashboard

Reproducible command:

```bash
./scripts/superset-create-kpi-dashboard.sh kpi3
```

Superset dashboard:

- Title: `KPI 3 - Air Quality Dashboard`
- URL: `http://localhost:18088/superset/dashboard/5/`
- Status: created and published.

Layout:

- Row 1:
  - `KPI - KPI3 Bad-Air AQI Share`
  - `KPI - KPI3 Bad-Air Share Trend`
- Row 2:
  - `KPI - KPI3 Counties by Bad-Air Share`
  - `KPI - KPI3 Bad-Air by Defining Parameter`

Current interaction status:

- Native dashboard filters are configured.
- Cross-filtering is enabled.
- Visible dashboard filters:
  - `Time range`: scoped to all four visible KPI 3 charts through `observation_date`.
  - `State`: scoped to all four visible KPI 3 charts through `state_code`.
  - `County`: scoped to all four visible KPI 3 charts through `county_name`.
  - `Defining parameter`: scoped to all four visible KPI 3 charts through `defining_parameter_name`.
- Cross-filtering emitters:
  - `KPI - KPI3 Counties by Bad-Air Share`
  - `KPI - KPI3 Bad-Air by Defining Parameter`
- KPI 3 SQL datasets preserve visible filter dimensions and let Superset calculate weighted bad-air share and average AQI in the active dashboard filter context.
- No AQI-category filter is exposed because visible KPI 3 charts use the fixed `AQI > 100` bad-air definition.

Polish notes from visual inspection:

- The trend chart is useful, but `avg_aqi` and `bad_air_pct` currently share one axis; later we should consider a mixed/dual-axis chart or separate charts.
- The counties chart is informative but crowded by state series; later it should likely become a cleaner top-county ranking with state handled as a dashboard filter.
- The defining-parameter donut chart is visually strong and should stay.

### KPI 3 Chart Reading Guide

General interpretation:

- All visible KPI 3 charts should be interpreted in the current filter context.
- Active filters are `Time range`, `State`, `County`, and `Defining parameter`.
- Bad-air means `AQI > 100`.
- Bad-air share is weighted as `SUM(bad_air_observation_count) / SUM(aqi_observation_count)`, not as a simple average of pre-aggregated percentages.
- Average AQI is weighted as `SUM(aqi_sum) / SUM(aqi_observation_count)`.

`KPI - KPI3 Bad-Air AQI Share`:

- Chart type: Big Number with Trendline.
- The large number is the latest monthly bad-air share within the active filter context.
- The line shows monthly bad-air share across the selected time range.
- Hover values on the line are monthly bad-air percentages.
- The percentage under the large number compares the latest displayed month with the previous displayed month.

`KPI - KPI3 Bad-Air Share Trend`:

- Chart type: monthly line chart.
- The chart shows weighted bad-air share and weighted average AQI over time after active filters are applied.
- Use this chart to compare whether bad-air frequency and average AQI move together in the selected geography and parameter context.

`KPI - KPI3 Counties by Bad-Air Share`:

- Chart type: horizontal bar chart.
- Each bar shows weighted bad-air share for a county after active filters are applied.
- State is used as a grouping/series dimension.
- Use this chart to identify counties with the highest share of AQI observations above 100 in the selected context.
- Applying state or county filters narrows the county ranking to the selected geography.

`KPI - KPI3 Bad-Air by Defining Parameter`:

- Chart type: donut chart.
- Each segment shows the count of bad-air AQI observations attributed to a defining parameter after active filters are applied.
- This chart shows contribution to bad-air observations, not bad-air percentage.
- Selecting a parameter narrows the rest of the KPI 3 dashboard to that parameter context.

### Dashboard 4: Accidents and Air Quality Relationship

Purpose:

- Explore whether accident frequency, severity share, or accident duration move together with degraded air quality.
- Keep the interpretation as association, not causation.
- Use this as the first cross-domain dashboard connecting US-Accidents and EPA AQS facts.

Current data supports this analysis because both domains are conformed through time and geography. The first implementation uses state plus month grain because it is stable, readable, and already proven in the combined monthly SQL. County plus month can be added later if we need finer local analysis.

Implemented SQL files:

| File | Purpose | Grain | Intended charts |
| --- | --- | --- | --- |
| `naloga6/sql/13_kpi_accidents_aqi_state_month_correlation_base.sql` | Base state/month accident and AQI measures for correlation visuals | state plus month | scatter charts, mixed chart |
| `naloga6/sql/14_kpi_accidents_aqi_correlation_summary.sql` | Overall correlation coefficients across state/month observations | one summary row | Big Number correlation cards |
| `naloga6/sql/15_kpi_accidents_aqi_state_correlation.sql` | Per-state correlation coefficients and observation counts | state | state ranking bar charts |

Implemented charts:

- `KPI - AQI Accident Count Correlation`: Big Number for `corr(accident_count, bad_air_pct)`.
- `KPI - AQI Duration Correlation`: Big Number for `corr(avg_duration_minutes, bad_air_pct)`.
- `KPI - AQI Severity Correlation`: Big Number for `corr(severe_accident_pct, bad_air_pct)`.
- `KPI - AQI vs Accident Count Scatter`: scatter chart comparing bad-air share with accident count by state/month.
- `KPI - AQI vs Duration Scatter`: scatter chart comparing bad-air share with average accident duration.
- `KPI - State AQI Accident Correlation Ranking`: bar chart ranking states by accident-count correlation with bad-air share.
- `KPI - Accidents and AQI Monthly Comparison`: mixed chart using accident count and bad-air share over time.

Interpretation rules:

- Positive correlation means the two measures tend to increase together in the selected grain.
- Negative correlation means one measure tends to increase while the other decreases.
- Correlation near zero means no strong linear relationship at the selected grain.
- Correlation does not imply air quality caused more or fewer accidents.

Implementation status:

- Local SQL validation command:

```bash
./scripts/run-kpi-sql.sh \
  naloga6/sql/13_kpi_accidents_aqi_state_month_correlation_base.sql \
  naloga6/sql/14_kpi_accidents_aqi_correlation_summary.sql \
  naloga6/sql/15_kpi_accidents_aqi_state_correlation.sql
```

- Validation result: `RESULT: OK`.
- State/month observation count: `3,957`.
- Overall `corr(accident_count, bad_air_pct)`: `0.1871`.
- Overall `corr(avg_duration_minutes, bad_air_pct)`: `-0.0074`.
- Overall `corr(severe_accident_pct, bad_air_pct)`: `-0.0414`.
- Superset SQL previews, virtual datasets, and graphical charts were created by rerunning:

```bash
./scripts/superset-create-kpi-assets.sh
```

Current status:

- Dashboard 4 SQL files are complete.
- Dashboard 4 SQL previews are complete.
- Dashboard 4 virtual datasets are complete.
- Dashboard 4 graphical charts are complete.
- Dashboard 4 layout/composition is complete.

Reproducible dashboard command:

```bash
./scripts/superset-create-kpi-dashboard.sh kpi4
```

Superset dashboard:

- Title: `Dashboard 4 - Accidents and Air Quality Relationship`
- URL: `http://localhost:18088/superset/dashboard/6/`
- Status: created and published.

Layout:

- Row 1:
  - `KPI - AQI Accident Count Correlation`
  - `KPI - AQI Duration Correlation`
  - `KPI - AQI Severity Correlation`
- Row 2:
  - `KPI - AQI vs Accident Count Scatter`
  - `KPI - AQI vs Duration Scatter`
- Row 3:
  - `KPI - State AQI Accident Correlation Ranking`
  - `KPI - Accidents and AQI Monthly Comparison`

Current interaction status:

- Native dashboard filters are configured.
- Cross-filtering is enabled.
- Drill-down/context-menu interaction is available on compatible visible charts.

Implemented Dashboard 4 interaction status:

- Dashboard rebuilt by running:

```bash
./scripts/superset-create-kpi-assets.sh
./scripts/superset-create-kpi-dashboard.sh kpi4
```

- Native filters added:
  - `Time range`: scoped to all seven visible Dashboard 4 charts through `metric_month`.
  - `State`: scoped to all seven visible Dashboard 4 charts through `state_code`.
- Cross-filtering enabled:
  - `KPI - AQI vs Accident Count Scatter` emits filters to all visible Dashboard 4 charts.
  - `KPI - AQI vs Duration Scatter` emits filters to all visible Dashboard 4 charts.
  - `KPI - State AQI Accident Correlation Ranking` emits filters to all visible Dashboard 4 charts.
  - `KPI - Accidents and AQI Monthly Comparison` emits filters to all visible Dashboard 4 charts.
- SQL and chart support added for interactive filters:
  - `13_kpi_accidents_aqi_state_month_correlation_base.sql` is the filter-aware source dataset for all visible Dashboard 4 charts.
  - The three correlation cards now compute chart-level SQL metrics over the filtered state/month observations instead of reading fixed one-row precomputed summary values.
  - `KPI - State AQI Accident Correlation Ranking` now computes per-state correlation from the same filtered state/month base dataset instead of reading the fixed per-state summary dataset.
  - Internal SQL `ORDER BY` was removed from the Dashboard 4 base virtual dataset so Superset can apply filtering and chart-level aggregation cleanly.
- No county filter was added because Dashboard 4 currently uses state/month grain, not county/month grain.
- No severity filter was added because severity appears as a relationship measure, not as a visible Dashboard 4 filtering dimension.
- No AQI category or threshold filter was added because the visible Dashboard 4 charts use the fixed `AQI > 100` bad-air share measure.
- No outlier filtering or value capping was added.

### Dashboard 4 Chart Reading Guide

General reading notes:

- Dashboard 4 compares accidents and air quality at state/month grain.
- The dashboard supports association analysis only. It does not prove that air quality causes accident frequency, duration, or severity to change.
- Active filters are selected in the dashboard filter bar: `Time range` and `State`.
- All visible Dashboard 4 charts should be interpreted in the current filter context.
- Positive correlation means the two measures tend to increase together in the selected state/month observations.
- Negative correlation means one measure tends to increase while the other decreases.
- Correlation near zero means there is no strong linear relationship at this grain.
- No outliers are removed or capped in Dashboard 4.

`KPI - AQI Accident Count Correlation`:

- Chart type: Big Number.
- Displays `CORR(accident_count, bad_air_pct)` over the currently selected state/month observations.
- Positive values mean higher bad-air share tends to appear with higher monthly accident counts.
- Negative values mean higher bad-air share tends to appear with lower monthly accident counts.
- Values near zero indicate little or no linear relationship between monthly accident count and bad-air share in the selected filter context.

`KPI - AQI Duration Correlation`:

- Chart type: Big Number.
- Displays `CORR(avg_duration_minutes, bad_air_pct)` over the currently selected state/month observations.
- Positive values mean higher bad-air share tends to appear with longer average accident duration.
- Negative values mean higher bad-air share tends to appear with shorter average accident duration.
- Values near zero indicate little or no linear relationship between average accident duration and bad-air share.

`KPI - AQI Severity Correlation`:

- Chart type: Big Number.
- Displays `CORR(severe_accident_pct, bad_air_pct)` over the currently selected state/month observations.
- Positive values mean higher bad-air share tends to appear with a higher severe-accident share.
- Negative values mean higher bad-air share tends to appear with a lower severe-accident share.
- Values near zero indicate little or no linear relationship between severe-accident share and bad-air share.

`KPI - AQI vs Accident Count Scatter`:

- Chart type: scatter plot.
- X-axis: bad-air observation percentage for a state/month.
- Y-axis: accident count for a state/month.
- Series/grouping: state.
- Each point represents a state/month observation after active filters are applied.
- Use this chart to see whether accident volume visually rises, falls, or stays scattered as bad-air share changes.

`KPI - AQI vs Duration Scatter`:

- Chart type: scatter plot.
- X-axis: bad-air observation percentage for a state/month.
- Y-axis: average accident duration in minutes for a state/month.
- Series/grouping: state.
- Each point represents a state/month observation after active filters are applied.
- Use this chart to inspect whether longer accident durations visually align with worse air-quality months.

`KPI - State AQI Accident Correlation Ranking`:

- Chart type: horizontal bar chart.
- Each bar represents one state's `CORR(accident_count, bad_air_pct)` computed from the currently selected months.
- Positive bars indicate states where monthly accident count and bad-air share tend to rise together.
- Negative bars indicate states where monthly accident count and bad-air share tend to move in opposite directions.
- If a state filter is applied, the ranking narrows to the selected state or states.

`KPI - Accidents and AQI Monthly Comparison`:

- Chart type: mixed time-series chart.
- Primary axis: monthly accident count.
- Secondary axis: monthly bad-air percentage.
- Use this chart to compare whether accident volume and bad-air share move together over time.
- This chart is useful for visual trend comparison, while the correlation cards summarize the linear relationship numerically.

Polish notes from visual inspection:

- The three correlation Big Number cards are useful, but later they should include clearer interpretation labels such as `weak positive` or `no meaningful linear relationship`.
- The scatter plots are directionally useful, but they can be visually distorted by outliers. Outliers are intentionally left visible for the current dashboard version.
- The duration scatter is also affected by extreme duration values. Outlier capping, filtering, or separate flagging is intentionally out of scope for the current dashboard version.
- The state correlation ranking is conceptually useful but visually dense. Later it should likely show top/bottom states or use a clearer sorted horizontal ranking.
- The monthly comparison chart is a good combined view and now receives the Dashboard 4 `Time range` and `State` filters.

## Next Session Handoff

Current stopping point:

- Four Superset dashboards are created, published, and configured with first-pass dashboard-native filters and cross-filtering.
- Dashboard 3: `KPI 1 - Accident Frequency Dashboard` at `http://localhost:18088/superset/dashboard/3/`.
- Dashboard 4: `KPI 2 - Accident Duration Dashboard` at `http://localhost:18088/superset/dashboard/4/`.
- Dashboard 5: `KPI 3 - Air Quality Dashboard` at `http://localhost:18088/superset/dashboard/5/`.
- Dashboard 6: `Dashboard 4 - Accidents and Air Quality Relationship` at `http://localhost:18088/superset/dashboard/6/`.
- Dashboard 3, Dashboard 4, Dashboard 5, and Dashboard 6 now have native filters and cross-filtering configured.
- General rule established: add filtering and interaction only for dimensions visible in the dashboard charts.
- General rule established: visible counting, average, percentage, percentile, and correlation charts should recompute from active dashboard filters where the chart semantics support filtering.
- General rule established: outliers remain in the data unless a later explicit modeling decision changes that.
- KPI 2 visual rule established: keep duration outliers in the data, but use median and p90 as the primary visible duration measures so extreme records do not flatten the chart scale.
- KPI 2 county visual correction: the broken row-level count/duration scatter was replaced with a top-county accident-count ranking using `SUM(accident_count)`.

Key interpretation to preserve:

- Dashboard 4 correlations are low at state/month grain.
- `corr(accident_count, bad_air_pct) = 0.1871`, which is only a weak positive relationship.
- `corr(avg_duration_minutes, bad_air_pct) = -0.0074`, which is effectively no linear relationship.
- `corr(severe_accident_pct, bad_air_pct) = -0.0414`, which is also effectively no meaningful linear relationship.
- Treat these as association checks only. They do not establish causation.

Primary next work:

- Perform final manual QA of Dashboards 3 through 6 after any browser refresh/cache effects settle.
- Capture final screenshots for the assignment report.
- Decide whether an additional combined executive dashboard is needed, or whether Dashboard 6 already satisfies the cross-domain story.

Reproducibility commands:

```bash
./scripts/run-kpi-sql.sh
./scripts/superset-create-kpi-assets.sh
./scripts/superset-create-kpi-dashboard.sh kpi1
./scripts/superset-create-kpi-dashboard.sh kpi2
./scripts/superset-create-kpi-dashboard.sh kpi3
./scripts/superset-create-kpi-dashboard.sh kpi4
```

## Open Design Decisions

- Confirm the dashboard fact path. Current recommendation: use v2 for the main dashboard and reserve v1 for validation or comparison.
- Define whether later combined dashboards should add finer county/month comparison beyond the current state/month comparison grain.
- Decide whether KPI 3 should continue using only fixed `AQI > 100` or also expose AQI category-based thresholds for user filtering.
- Decide whether severe accidents for PA2 means the highest `severity_level`, a selected threshold, or a dashboard filter controlled by the user.
- Decide whether SQL artifacts should live only as Superset virtual datasets or also as PostgreSQL views in `dw`.
