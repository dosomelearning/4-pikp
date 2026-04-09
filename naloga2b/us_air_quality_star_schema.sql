-- Star schema extension for Source 2: US Air Quality (daily_aqi_by_county)
-- PostgreSQL DDL (warehouse-style schema)
-- Modeling strategy:
--   - Keep legacy fact table unchanged: dw.fact_air_quality_daily (v1)
--   - Add new snowflake-aware fact table: dw.fact_air_quality_daily_v2

CREATE SCHEMA IF NOT EXISTS dw;

CREATE TABLE IF NOT EXISTS dw.dim_aqi_category (
    aqi_category_key         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    aqi_category_nk          varchar(64) NOT NULL,
    aqi_category_name        varchar(64) NOT NULL,
    valid_from               timestamp NOT NULL,
    valid_to                 timestamp NOT NULL DEFAULT '9999-12-31 23:59:59',
    is_current               boolean NOT NULL DEFAULT true,
    CHECK (valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS dw.dim_defining_parameter (
    defining_parameter_key   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    defining_parameter_nk    varchar(64) NOT NULL,
    defining_parameter_name  varchar(64) NOT NULL,
    valid_from               timestamp NOT NULL,
    valid_to                 timestamp NOT NULL DEFAULT '9999-12-31 23:59:59',
    is_current               boolean NOT NULL DEFAULT true,
    CHECK (valid_to >= valid_from)
);

-- Legacy fact table (v1): unchanged shape
CREATE TABLE IF NOT EXISTS dw.fact_air_quality_daily (
    source_state_code            varchar(2) NOT NULL,
    source_county_code           varchar(3) NOT NULL,
    source_date                  date NOT NULL,
    time_key                     integer NOT NULL REFERENCES dw.dim_time(time_key),
    location_key                 bigint NOT NULL REFERENCES dw.dim_location(location_key),
    aqi_category_key             bigint NOT NULL REFERENCES dw.dim_aqi_category(aqi_category_key),
    defining_parameter_key       bigint NOT NULL REFERENCES dw.dim_defining_parameter(defining_parameter_key),
    aqi                          integer NOT NULL,
    number_of_sites_reporting    integer NOT NULL,
    defining_site_code           varchar(32),
    PRIMARY KEY (source_state_code, source_county_code, source_date),
    CHECK (aqi >= 0),
    CHECK (number_of_sites_reporting >= 0)
);

-- New fact table (v2): snowflake location path
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

CREATE INDEX IF NOT EXISTS ix_fact_air_quality_daily_time_key
    ON dw.fact_air_quality_daily (time_key);
CREATE INDEX IF NOT EXISTS ix_fact_air_quality_daily_location_key
    ON dw.fact_air_quality_daily (location_key);
CREATE INDEX IF NOT EXISTS ix_fact_air_quality_daily_aqi_category_key
    ON dw.fact_air_quality_daily (aqi_category_key);
CREATE INDEX IF NOT EXISTS ix_fact_air_quality_daily_defining_parameter_key
    ON dw.fact_air_quality_daily (defining_parameter_key);

CREATE INDEX IF NOT EXISTS ix_fact_air_quality_daily_v2_time_key
    ON dw.fact_air_quality_daily_v2 (time_key);
CREATE INDEX IF NOT EXISTS ix_fact_air_quality_daily_v2_county_key
    ON dw.fact_air_quality_daily_v2 (county_key);
CREATE INDEX IF NOT EXISTS ix_fact_air_quality_daily_v2_aqi_category_key
    ON dw.fact_air_quality_daily_v2 (aqi_category_key);
CREATE INDEX IF NOT EXISTS ix_fact_air_quality_daily_v2_defining_parameter_key
    ON dw.fact_air_quality_daily_v2 (defining_parameter_key);

-- Type 2 helper indexes: one current version per natural key
CREATE UNIQUE INDEX IF NOT EXISTS ux_dim_aqi_category_current_nk
    ON dw.dim_aqi_category (aqi_category_nk)
    WHERE is_current = true;

CREATE UNIQUE INDEX IF NOT EXISTS ux_dim_defining_parameter_current_nk
    ON dw.dim_defining_parameter (defining_parameter_nk)
    WHERE is_current = true;
