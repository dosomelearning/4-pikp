-- KPI 2: Accident count versus duration base rows for county charts.
-- Grain: one row per accident.
-- Intended Superset chart: scatter or bubble chart by county.
-- Dashboard filters: accident_date, state_code, county_name, severity_level,
-- weather_condition_name, primary_road_signal.

SELECT
    f.start_time::date AS accident_date,
    date_trunc('month', f.start_time)::date AS metric_month,
    c.state_code,
    c.county_name,
    s.severity_level,
    w.weather_condition_name,
    CASE
        WHEN r.traffic_signal THEN 'Traffic signal'
        WHEN r.junction THEN 'Junction'
        WHEN r.crossing THEN 'Crossing'
        WHEN r.stop_sign THEN 'Stop sign'
        WHEN r.railway THEN 'Railway'
        WHEN r.station THEN 'Station'
        WHEN r.amenity THEN 'Amenity'
        WHEN r.bump THEN 'Bump'
        WHEN r.traffic_calming THEN 'Traffic calming'
        WHEN r.give_way THEN 'Give way'
        WHEN r.no_exit THEN 'No exit'
        WHEN r.roundabout THEN 'Roundabout'
        WHEN r.turning_loop THEN 'Turning loop'
        ELSE 'No selected road signal'
    END AS primary_road_signal,
    f.accident_duration_minutes,
    1 AS accident_count,
    CASE WHEN s.severity_level = 4 THEN 1 ELSE 0 END AS severe_accident_count
FROM dw.fact_accident_v2 f
JOIN dw.dim_county c
  ON c.county_key = f.county_key
 AND c.is_current = true
JOIN dw.dim_severity s
  ON s.severity_key = f.severity_key
 AND s.is_current = true
JOIN dw.dim_weather_condition w
  ON w.weather_condition_key = f.weather_condition_key
 AND w.is_current = true
JOIN dw.dim_road_condition r
  ON r.road_condition_key = f.road_condition_key
 AND r.is_current = true;
