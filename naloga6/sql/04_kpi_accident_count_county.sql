-- KPI 1: Accident count by date, county, and severity.
-- Grain: one row per accident date, state, county, and severity level.
-- Intended Superset chart: horizontal bar chart.
-- Dashboard filters: accident_date, state_code, county_name, severity_level.

SELECT
    f.start_time::date AS accident_date,
    c.state_code,
    c.county_name,
    s.severity_level,
    COUNT(*) AS accident_count,
    COUNT(*) FILTER (WHERE s.severity_level = 4) AS severe_accident_count,
    ROUND(100.0 * COUNT(*) FILTER (WHERE s.severity_level = 4) / NULLIF(COUNT(*), 0), 2) AS severe_accident_pct,
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
    c.state_code,
    c.county_name,
    s.severity_level;
