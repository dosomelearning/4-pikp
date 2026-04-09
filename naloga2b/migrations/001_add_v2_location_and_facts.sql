-- naloga2b incremental migration: add v2 location snowflake + v2 fact tables
-- Safe to run on an existing v1 warehouse (additive only).
-- No drops, no rewrites of existing tables.

BEGIN;

CREATE SCHEMA IF NOT EXISTS dw;

-- New conformed county dimension (v2 path)
CREATE TABLE IF NOT EXISTS dw.dim_county (
    county_key             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    county_nk              varchar(200) NOT NULL,
    county_name            varchar(100) NOT NULL,
    state_code             varchar(10) NOT NULL,
    country_code           varchar(10) NOT NULL,
    source_county_code     varchar(3),
    valid_from             timestamp NOT NULL,
    valid_to               timestamp NOT NULL DEFAULT '9999-12-31 23:59:59',
    is_current             boolean NOT NULL DEFAULT true,
    CHECK (valid_to >= valid_from)
);

-- New detailed location dimension normalized under county (v2 path)
CREATE TABLE IF NOT EXISTS dw.dim_streetcity (
    streetcity_key         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    streetcity_nk          varchar(400) NOT NULL,
    county_key             bigint NOT NULL REFERENCES dw.dim_county(county_key),
    street                 varchar(255),
    city                   varchar(100),
    zipcode                varchar(20),
    timezone_name          varchar(100),
    valid_from             timestamp NOT NULL,
    valid_to               timestamp NOT NULL DEFAULT '9999-12-31 23:59:59',
    is_current             boolean NOT NULL DEFAULT true,
    CHECK (valid_to >= valid_from)
);

-- New accident fact (v2), keyed by source accident id for direct comparison with v1.
CREATE TABLE IF NOT EXISTS dw.fact_accident_v2 (
    source_accident_id             varchar(32) PRIMARY KEY,
    start_time_key                 integer NOT NULL REFERENCES dw.dim_time(time_key),
    end_time_key                   integer NOT NULL REFERENCES dw.dim_time(time_key),
    streetcity_key                 bigint NOT NULL REFERENCES dw.dim_streetcity(streetcity_key),
    county_key                     bigint NOT NULL REFERENCES dw.dim_county(county_key),
    weather_condition_key          bigint NOT NULL REFERENCES dw.dim_weather_condition(weather_condition_key),
    road_condition_key             bigint NOT NULL REFERENCES dw.dim_road_condition(road_condition_key),
    severity_key                   integer NOT NULL REFERENCES dw.dim_severity(severity_key),
    start_time                     timestamp NOT NULL,
    end_time                       timestamp NOT NULL,
    accident_duration_minutes      numeric(12,2) NOT NULL,
    road_affected_length_mi        numeric(10,2),
    start_latitude                 numeric(9,6) NOT NULL,
    start_longitude                numeric(9,6) NOT NULL,
    end_latitude                   numeric(9,6),
    end_longitude                  numeric(9,6),
    CHECK (end_time >= start_time),
    CHECK (accident_duration_minutes >= 0),
    CHECK (road_affected_length_mi IS NULL OR road_affected_length_mi >= 0),
    CHECK (start_latitude BETWEEN -90 AND 90),
    CHECK (start_longitude BETWEEN -180 AND 180),
    CHECK (end_latitude IS NULL OR end_latitude BETWEEN -90 AND 90),
    CHECK (end_longitude IS NULL OR end_longitude BETWEEN -180 AND 180)
);

-- New air-quality fact (v2), county-based FK path.
CREATE TABLE IF NOT EXISTS dw.fact_air_quality_daily_v2 (
    source_state_code            varchar(2) NOT NULL,
    source_county_code           varchar(3) NOT NULL,
    source_date                  date NOT NULL,
    time_key                     integer NOT NULL REFERENCES dw.dim_time(time_key),
    county_key                   bigint NOT NULL REFERENCES dw.dim_county(county_key),
    aqi_category_key             bigint NOT NULL REFERENCES dw.dim_aqi_category(aqi_category_key),
    defining_parameter_key       bigint NOT NULL REFERENCES dw.dim_defining_parameter(defining_parameter_key),
    aqi                          integer NOT NULL,
    number_of_sites_reporting    integer NOT NULL,
    defining_site_code           varchar(32),
    PRIMARY KEY (source_state_code, source_county_code, source_date),
    CHECK (aqi >= 0),
    CHECK (number_of_sites_reporting >= 0)
);

-- Indexes for new dimensions
CREATE UNIQUE INDEX IF NOT EXISTS ux_dim_county_current_nk
    ON dw.dim_county (county_nk)
    WHERE is_current = true;

CREATE UNIQUE INDEX IF NOT EXISTS ux_dim_county_current_code
    ON dw.dim_county (country_code, state_code, source_county_code)
    WHERE is_current = true
      AND source_county_code IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_dim_streetcity_current_nk
    ON dw.dim_streetcity (streetcity_nk)
    WHERE is_current = true;

CREATE INDEX IF NOT EXISTS ix_dim_streetcity_county_key
    ON dw.dim_streetcity (county_key);

-- Indexes for new v2 fact tables
CREATE INDEX IF NOT EXISTS ix_fact_accident_v2_start_time_key
    ON dw.fact_accident_v2 (start_time_key);

CREATE INDEX IF NOT EXISTS ix_fact_accident_v2_end_time_key
    ON dw.fact_accident_v2 (end_time_key);

CREATE INDEX IF NOT EXISTS ix_fact_accident_v2_streetcity_key
    ON dw.fact_accident_v2 (streetcity_key);

CREATE INDEX IF NOT EXISTS ix_fact_accident_v2_county_key
    ON dw.fact_accident_v2 (county_key);

CREATE INDEX IF NOT EXISTS ix_fact_accident_v2_weather_condition_key
    ON dw.fact_accident_v2 (weather_condition_key);

CREATE INDEX IF NOT EXISTS ix_fact_accident_v2_road_condition_key
    ON dw.fact_accident_v2 (road_condition_key);

CREATE INDEX IF NOT EXISTS ix_fact_accident_v2_severity_key
    ON dw.fact_accident_v2 (severity_key);

CREATE INDEX IF NOT EXISTS ix_fact_air_quality_daily_v2_time_key
    ON dw.fact_air_quality_daily_v2 (time_key);

CREATE INDEX IF NOT EXISTS ix_fact_air_quality_daily_v2_county_key
    ON dw.fact_air_quality_daily_v2 (county_key);

CREATE INDEX IF NOT EXISTS ix_fact_air_quality_daily_v2_aqi_category_key
    ON dw.fact_air_quality_daily_v2 (aqi_category_key);

CREATE INDEX IF NOT EXISTS ix_fact_air_quality_daily_v2_defining_parameter_key
    ON dw.fact_air_quality_daily_v2 (defining_parameter_key);

COMMIT;
