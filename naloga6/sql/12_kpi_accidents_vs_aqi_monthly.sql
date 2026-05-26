-- Combined KPI view: accident count, duration, and AQI by state and month.
-- Grain: one row per state and month where both accident and AQI data exist.
-- Intended Superset chart: mixed time-series chart or scatter plot.

WITH accident_monthly AS (
    SELECT
        c.state_code,
        date_trunc('month', f.start_time)::date AS metric_month,
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
        c.state_code,
        date_trunc('month', f.start_time)::date
),
aqi_monthly AS (
    SELECT
        c.state_code,
        date_trunc('month', a.source_date)::date AS metric_month,
        COUNT(*) AS aqi_observation_count,
        COUNT(*) FILTER (WHERE a.aqi > 100) AS bad_air_observation_count,
        ROUND(100.0 * COUNT(*) FILTER (WHERE a.aqi > 100) / NULLIF(COUNT(*), 0), 2) AS bad_air_pct,
        ROUND(AVG(a.aqi), 2) AS avg_aqi
    FROM dw.fact_air_quality_daily_v2 a
    JOIN dw.dim_county c
      ON c.county_key = a.county_key
     AND c.is_current = true
    GROUP BY
        c.state_code,
        date_trunc('month', a.source_date)::date
)
SELECT
    a.state_code,
    a.metric_month,
    a.accident_count,
    a.severe_accident_count,
    ROUND(100.0 * a.severe_accident_count / NULLIF(a.accident_count, 0), 2) AS severe_accident_pct,
    a.avg_duration_minutes,
    q.aqi_observation_count,
    q.bad_air_observation_count,
    q.bad_air_pct,
    q.avg_aqi
FROM accident_monthly a
JOIN aqi_monthly q
  ON q.state_code = a.state_code
 AND q.metric_month = a.metric_month
ORDER BY
    a.metric_month,
    a.state_code;
