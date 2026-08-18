-- =========================================================
-- SILVER: stg_storm_events
-- ---------------------------------------------------------
-- Clean, typed, union of all 4 years. Applies the junk-drop
-- list from plan §2.1:
--   - Drops junk / redundant / too-sparse columns
--   - Casts dates -> TIMESTAMP, counts -> INT, lat/lon -> NUMBER
--   - Parses damage tokens (K/M/B) -> numeric USD
--   - Flags test rows (EVENT_ID starting '999') as is_test_event
-- Primary key = EVENT_ID (unique across years).
-- =========================================================

WITH bronze_2022 AS (
    SELECT * FROM {{ ref('bronze_storm_events_2022') }}
),
bronze_2023 AS (
    SELECT * FROM {{ ref('bronze_storm_events_2023') }}
),
bronze_2024 AS (
    SELECT * FROM {{ ref('bronze_storm_events_2024') }}
),
bronze_2025 AS (
    SELECT * FROM {{ ref('bronze_storm_events_2025') }}
),

-- Union all years; keep only non-junk columns (drop list §2.1a-b)
raw_union AS (
    SELECT
        EVENT_ID, EPISODE_ID, STATE, YEAR, EVENT_TYPE,
        CZ_FIPS, CZ_NAME, WFO,
        BEGIN_DATE_TIME, END_DATE_TIME, CZ_TIMEZONE,
        INJURIES_DIRECT, INJURIES_INDIRECT, DEATHS_DIRECT, DEATHS_INDIRECT,
        DAMAGE_PROPERTY, DAMAGE_CROPS, SOURCE,
        BEGIN_LAT, BEGIN_LON, END_LAT, END_LON,
        EPISODE_NARRATIVE, EVENT_NARRATIVE
    FROM bronze_2022
    UNION ALL
    SELECT
        EVENT_ID, EPISODE_ID, STATE, YEAR, EVENT_TYPE,
        CZ_FIPS, CZ_NAME, WFO,
        BEGIN_DATE_TIME, END_DATE_TIME, CZ_TIMEZONE,
        INJURIES_DIRECT, INJURIES_INDIRECT, DEATHS_DIRECT, DEATHS_INDIRECT,
        DAMAGE_PROPERTY, DAMAGE_CROPS, SOURCE,
        BEGIN_LAT, BEGIN_LON, END_LAT, END_LON,
        EPISODE_NARRATIVE, EVENT_NARRATIVE
    FROM bronze_2023
    UNION ALL
    SELECT
        EVENT_ID, EPISODE_ID, STATE, YEAR, EVENT_TYPE,
        CZ_FIPS, CZ_NAME, WFO,
        BEGIN_DATE_TIME, END_DATE_TIME, CZ_TIMEZONE,
        INJURIES_DIRECT, INJURIES_INDIRECT, DEATHS_DIRECT, DEATHS_INDIRECT,
        DAMAGE_PROPERTY, DAMAGE_CROPS, SOURCE,
        BEGIN_LAT, BEGIN_LON, END_LAT, END_LON,
        EPISODE_NARRATIVE, EVENT_NARRATIVE
    FROM bronze_2024
    UNION ALL
    SELECT
        EVENT_ID, EPISODE_ID, STATE, YEAR, EVENT_TYPE,
        CZ_FIPS, CZ_NAME, WFO,
        BEGIN_DATE_TIME, END_DATE_TIME, CZ_TIMEZONE,
        INJURIES_DIRECT, INJURIES_INDIRECT, DEATHS_DIRECT, DEATHS_INDIRECT,
        DAMAGE_PROPERTY, DAMAGE_CROPS, SOURCE,
        BEGIN_LAT, BEGIN_LON, END_LAT, END_LON,
        EPISODE_NARRATIVE, EVENT_NARRATIVE
    FROM bronze_2025
)

SELECT
    EVENT_ID,
    EPISODE_ID,
    STATE,
    TRY_TO_NUMBER(YEAR)                                      AS year,
    EVENT_TYPE,
    CZ_FIPS,
    CZ_NAME,
    WFO,
    -- Standardize to ISO timestamp (explicit parse of 'DD-MON-YY HH:MM:SS')
    TRY_TO_TIMESTAMP(BEGIN_DATE_TIME, 'DD-MON-YY HH24:MI:SS') AS begin_date_time,
    TRY_TO_TIMESTAMP(END_DATE_TIME,   'DD-MON-YY HH24:MI:SS') AS end_date_time,
    CZ_TIMEZONE,
    -- Counts -> integer
    TRY_TO_NUMBER(INJURIES_DIRECT)                           AS injuries_direct,
    TRY_TO_NUMBER(INJURIES_INDIRECT)                         AS injuries_indirect,
    TRY_TO_NUMBER(DEATHS_DIRECT)                             AS deaths_direct,
    TRY_TO_NUMBER(DEATHS_INDIRECT)                           AS deaths_indirect,
    -- Damage -> numeric USD (K/M/B)
    {{ parse_damage_usd('DAMAGE_PROPERTY') }}                AS damage_property_usd,
    {{ parse_damage_usd('DAMAGE_CROPS') }}                   AS damage_crops_usd,
    SOURCE,
    -- Coordinates -> numeric
    TRY_TO_NUMBER(BEGIN_LAT)                                 AS begin_lat,
    TRY_TO_NUMBER(BEGIN_LON)                                 AS begin_lon,
    TRY_TO_NUMBER(END_LAT)                                   AS end_lat,
    TRY_TO_NUMBER(END_LON)                                   AS end_lon,
    EPISODE_NARRATIVE,
    EVENT_NARRATIVE,
    -- Flag test/placeholder rows (EVENT_ID starting '999')
    (EVENT_ID LIKE '999%')                                   AS is_test_event

FROM raw_union
