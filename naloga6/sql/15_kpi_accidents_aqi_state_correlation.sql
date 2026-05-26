-- Dashboard 4: Per-state accident/AQI correlation summary.
-- Grain: one row per state.
-- Intended Superset chart: state ranking bar chart.
-- Interpretation note: correlation is descriptive association, not causation.

WITH relationship_base AS (
    SELECT *
    FROM (
        WITH accident_monthly AS (
            SELECT
                c.state_code,
                date_trunc('month', f.start_time)::date AS metric_month,
                COUNT(*) AS accident_count,
                COUNT(*) FILTER (WHERE s.severity_level = 4) AS severe_accident_count,
                100.0 * COUNT(*) FILTER (WHERE s.severity_level = 4) / NULLIF(COUNT(*), 0) AS severe_accident_pct,
                AVG(f.accident_duration_minutes) AS avg_duration_minutes
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
                100.0 * COUNT(*) FILTER (WHERE a.aqi > 100) / NULLIF(COUNT(*), 0) AS bad_air_pct,
                AVG(a.aqi) AS avg_aqi
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
            a.severe_accident_pct,
            a.avg_duration_minutes,
            q.aqi_observation_count,
            q.bad_air_pct,
            q.avg_aqi
        FROM accident_monthly a
        JOIN aqi_monthly q
          ON q.state_code = a.state_code
         AND q.metric_month = a.metric_month
    ) base
)
SELECT
    state_code,
    COUNT(*) AS state_month_observation_count,
    ROUND(CORR(accident_count::numeric, bad_air_pct)::numeric, 4) AS corr_accident_count_bad_air_pct,
    ROUND(CORR(avg_duration_minutes::numeric, bad_air_pct)::numeric, 4) AS corr_avg_duration_bad_air_pct,
    ROUND(CORR(severe_accident_pct::numeric, bad_air_pct)::numeric, 4) AS corr_severe_accident_pct_bad_air_pct,
    ROUND(AVG(accident_count), 2) AS avg_monthly_accident_count,
    ROUND(AVG(bad_air_pct), 2) AS avg_bad_air_pct,
    ROUND(AVG(avg_aqi), 2) AS avg_aqi
FROM relationship_base
GROUP BY state_code
HAVING COUNT(*) >= 12
ORDER BY
    corr_accident_count_bad_air_pct DESC NULLS LAST,
    state_code;
