-- Star schema for Source 1: US-Accidents
-- PostgreSQL DDL (warehouse-style schema)

CREATE SCHEMA IF NOT EXISTS dw;

-- Time dimension (used as role-playing dimension for start and end time)
CREATE TABLE IF NOT EXISTS dw.dim_time (
    time_key               integer PRIMARY KEY, -- smart surrogate key: YYYYMMDDHH (hour grain)
    date_value             date NOT NULL,
    year_num               integer NOT NULL,
    month_num              integer NOT NULL,
    day_num                integer NOT NULL,
    hour_num               integer NOT NULL,
    day_of_week_num        integer NOT NULL,
    day_of_week_name       varchar(16) NOT NULL,
    is_weekend             boolean NOT NULL
);

CREATE TABLE IF NOT EXISTS dw.dim_location (
    location_key           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    location_nk            varchar(300) NOT NULL,
    street                 varchar(255),
    city                   varchar(100),
    county                 varchar(100),
    state_code             varchar(10),
    zipcode                varchar(20),
    country_code           varchar(10),
    timezone_name          varchar(100),
    valid_from             timestamp NOT NULL,
    valid_to               timestamp NOT NULL DEFAULT '9999-12-31 23:59:59',
    is_current             boolean NOT NULL DEFAULT true,
    CHECK (valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS dw.dim_weather_condition (
    weather_condition_key  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    weather_condition_nk   varchar(120) NOT NULL,
    weather_condition_name varchar(120) NOT NULL,
    valid_from             timestamp NOT NULL,
    valid_to               timestamp NOT NULL DEFAULT '9999-12-31 23:59:59',
    is_current             boolean NOT NULL DEFAULT true,
    CHECK (valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS dw.dim_road_condition (
    road_condition_key     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    road_condition_nk      varchar(200) NOT NULL,
    amenity                boolean NOT NULL DEFAULT false,
    bump                   boolean NOT NULL DEFAULT false,
    crossing               boolean NOT NULL DEFAULT false,
    give_way               boolean NOT NULL DEFAULT false,
    junction               boolean NOT NULL DEFAULT false,
    no_exit                boolean NOT NULL DEFAULT false,
    railway                boolean NOT NULL DEFAULT false,
    roundabout             boolean NOT NULL DEFAULT false,
    station                boolean NOT NULL DEFAULT false,
    stop_sign              boolean NOT NULL DEFAULT false,
    traffic_calming        boolean NOT NULL DEFAULT false,
    traffic_signal         boolean NOT NULL DEFAULT false,
    turning_loop           boolean NOT NULL DEFAULT false,
    valid_from             timestamp NOT NULL,
    valid_to               timestamp NOT NULL DEFAULT '9999-12-31 23:59:59',
    is_current             boolean NOT NULL DEFAULT true,
    CHECK (valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS dw.dim_severity (
    severity_key           integer PRIMARY KEY,
    severity_level         integer NOT NULL,
    valid_from             timestamp NOT NULL,
    valid_to               timestamp NOT NULL DEFAULT '9999-12-31 23:59:59',
    is_current             boolean NOT NULL DEFAULT true,
    CHECK (valid_to >= valid_from)
);

-- Fact table: one row per accident event (source ID)
CREATE TABLE IF NOT EXISTS dw.fact_accident (
    source_accident_id             varchar(32) PRIMARY KEY,

    -- Dimension foreign keys
    start_time_key                 integer NOT NULL REFERENCES dw.dim_time(time_key),
    end_time_key                   integer NOT NULL REFERENCES dw.dim_time(time_key),
    location_key                   bigint NOT NULL REFERENCES dw.dim_location(location_key),
    county_location_key            bigint NOT NULL REFERENCES dw.dim_location(location_key),
    weather_condition_key          bigint NOT NULL REFERENCES dw.dim_weather_condition(weather_condition_key),
    road_condition_key             bigint NOT NULL REFERENCES dw.dim_road_condition(road_condition_key),
    severity_key                   integer NOT NULL REFERENCES dw.dim_severity(severity_key),

    -- Measures requested by specification
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

CREATE INDEX IF NOT EXISTS ix_fact_accident_start_time_key
    ON dw.fact_accident (start_time_key);

CREATE INDEX IF NOT EXISTS ix_fact_accident_end_time_key
    ON dw.fact_accident (end_time_key);

CREATE INDEX IF NOT EXISTS ix_fact_accident_location_key
    ON dw.fact_accident (location_key);

CREATE INDEX IF NOT EXISTS ix_fact_accident_county_location_key
    ON dw.fact_accident (county_location_key);

CREATE INDEX IF NOT EXISTS ix_fact_accident_weather_condition_key
    ON dw.fact_accident (weather_condition_key);

CREATE INDEX IF NOT EXISTS ix_fact_accident_road_condition_key
    ON dw.fact_accident (road_condition_key);

CREATE INDEX IF NOT EXISTS ix_fact_accident_severity_key
    ON dw.fact_accident (severity_key);

-- Type 2 helper indexes: one current version per natural key
CREATE UNIQUE INDEX IF NOT EXISTS ux_dim_location_current_nk
    ON dw.dim_location (location_nk)
    WHERE is_current = true;

CREATE UNIQUE INDEX IF NOT EXISTS ux_dim_weather_condition_current_nk
    ON dw.dim_weather_condition (weather_condition_nk)
    WHERE is_current = true;

CREATE UNIQUE INDEX IF NOT EXISTS ux_dim_road_condition_current_nk
    ON dw.dim_road_condition (road_condition_nk)
    WHERE is_current = true;

CREATE UNIQUE INDEX IF NOT EXISTS ux_dim_severity_current_level
    ON dw.dim_severity (severity_level)
    WHERE is_current = true;
