-- KPI 3: Bad-air AQI share base rows for county charts.
-- Grain: one row per AQI source date, state, county, and defining parameter.
-- Intended Superset chart: horizontal bar chart by county.
-- Dashboard filters: observation_date, state_code, county_name, defining_parameter_name.

SELECT
    a.source_date AS observation_date,
    date_trunc('month', a.source_date)::date AS metric_month,
    c.state_code,
    c.county_name,
    p.defining_parameter_name,
    COUNT(*) AS aqi_observation_count,
    COUNT(*) FILTER (WHERE a.aqi > 100) AS bad_air_observation_count,
    SUM(a.aqi) AS aqi_sum,
    ROUND(100.0 * COUNT(*) FILTER (WHERE a.aqi > 100) / NULLIF(COUNT(*), 0), 2) AS bad_air_pct,
    ROUND(AVG(a.aqi), 2) AS avg_aqi,
    MAX(a.aqi) AS max_aqi
FROM dw.fact_air_quality_daily_v2 a
JOIN dw.dim_county c
  ON c.county_key = a.county_key
 AND c.is_current = true
JOIN dw.dim_defining_parameter p
  ON p.defining_parameter_key = a.defining_parameter_key
 AND p.is_current = true
GROUP BY
    a.source_date,
    date_trunc('month', a.source_date)::date,
    c.state_code,
    c.county_name,
    p.defining_parameter_name;
