-- KPI 1: Accident count by date, month, geography, and severity.
-- Grain: one row per accident date, accident start month, state, county, and severity level.
-- Intended Superset chart: Big Number with Trendline / monthly time-series line.
-- Dashboard filters: accident_date, state_code, county_name, severity_level.

SELECT
    f.start_time::date AS accident_date,
    date_trunc('month', f.start_time)::date AS metric_month,
    c.state_code,
    c.county_name,
    s.severity_level,
    COUNT(*) AS accident_count,
    COUNT(*) FILTER (WHERE s.severity_level = 4) AS severe_accident_count,
    ROUND(AVG(f.accident_duration_minutes), 2) AS avg_duration_minutes
FROM dw.fact_accident_v2 f
JOIN dw.dim_county c
  ON c.county_key = f.county_key
 AND c.is_current = true
JOIN dw.dim_severity s
  ON s.severity_key = f.severity_key
 AND s.is_current = true
GROUP BY
    f.start_time::date,
    date_trunc('month', f.start_time)::date,
    c.state_code,
    c.county_name,
    s.severity_level;
