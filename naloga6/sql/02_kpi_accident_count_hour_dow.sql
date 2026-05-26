-- KPI 1: Accident count by date, geography, weekday, hour, and severity.
-- Grain: one row per accident date, state, county, weekday, hour, and severity level.
-- Intended Superset chart: heatmap.
-- Dashboard filters: accident_date, state_code, county_name, severity_level.

SELECT
    f.start_time::date AS accident_date,
    c.state_code,
    c.county_name,
    t.day_of_week_num,
    t.day_of_week_name,
    t.hour_num,
    s.severity_level,
    COUNT(*) AS accident_count,
    COUNT(*) FILTER (WHERE s.severity_level = 4) AS severe_accident_count,
    ROUND(AVG(f.accident_duration_minutes), 2) AS avg_duration_minutes
FROM dw.fact_accident_v2 f
JOIN dw.dim_county c
  ON c.county_key = f.county_key
 AND c.is_current = true
JOIN dw.dim_time t
  ON t.time_key = f.start_time_key
JOIN dw.dim_severity s
  ON s.severity_key = f.severity_key
 AND s.is_current = true
GROUP BY
    f.start_time::date,
    c.state_code,
    c.county_name,
    t.day_of_week_num,
    t.day_of_week_name,
    t.hour_num,
    s.severity_level;
