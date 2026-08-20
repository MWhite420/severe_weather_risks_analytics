-- =========================================================
-- GOLD: gold_storm_events
-- ---------------------------------------------------------
-- Power BI-ready mart, one row per event (grain = EVENT_ID).
-- Built from SILVER.SILVER_STORM_EVENTS.
--
-- POWER BI TYPE CONTRACT (plan §2.2):
--   TIMESTAMP      begin_datetime, end_datetime
--   INT            year, month, event_count, injuries_total, deaths_total
--   NUMBER(18,2)   damage_property_usd, damage_crops_usd,
--                  financial_impact_usd, severity_risk_score
--   VARCHAR        state, state_type, month_name, event_type,
--                  cz_name, cz_fips, wfo
--   BOOLEAN        is_tornado, is_flood, is_test_event
--
-- Rules: real SQL NULL only (no text 'NULL' / empty strings in
-- numerics/dates); money as plain decimals (Power BI formats $).
--
-- FILTER: only the 50 real US states are kept. US territories
-- (Puerto Rico, Guam, American Samoa, US Virgin Islands, DC) and
-- all 13 marine/offshore zones are EXCLUDED.
-- =========================================================

WITH silver AS (
    SELECT * FROM {{ ref('silver_storm_events') }}
),

-- Only the 50 real US states qualify. Territories and marine zones
-- are excluded (see WHERE).
us_states AS (
    SELECT column1 AS state_name FROM VALUES
        ('ALABAMA'), ('ALASKA'), ('ARIZONA'), ('ARKANSAS'), ('CALIFORNIA'),
        ('COLORADO'), ('CONNECTICUT'), ('DELAWARE'), ('FLORIDA'), ('GEORGIA'),
        ('HAWAII'), ('IDAHO'), ('ILLINOIS'), ('INDIANA'), ('IOWA'),
        ('KANSAS'), ('KENTUCKY'), ('LOUISIANA'), ('MAINE'), ('MARYLAND'),
        ('MASSACHUSETTS'), ('MICHIGAN'), ('MINNESOTA'), ('MISSISSIPPI'), ('MISSOURI'),
        ('MONTANA'), ('NEBRASKA'), ('NEVADA'), ('NEW HAMPSHIRE'), ('NEW JERSEY'),
        ('NEW MEXICO'), ('NEW YORK'), ('NORTH CAROLINA'), ('NORTH DAKOTA'), ('OHIO'),
        ('OKLAHOMA'), ('OREGON'), ('PENNSYLVANIA'), ('RHODE ISLAND'), ('SOUTH CAROLINA'),
        ('SOUTH DAKOTA'), ('TENNESSEE'), ('TEXAS'), ('UTAH'), ('VERMONT'),
        ('VIRGINIA'), ('WASHINGTON'), ('WEST VIRGINIA'), ('WISCONSIN'), ('WYOMING')
)

SELECT
    -- identity / grain
    s.event_id,

    -- dimensions (always a real US state now)
    s.state,
    'STATE' AS state_type,
    s.year,
    MONTH(s.begin_date_time)                               AS month,
    TO_CHAR(s.begin_date_time, 'MMMM')                     AS month_name,
    s.event_type,
    s.cz_name,
    s.cz_fips,
    s.wfo,

    -- time (TIMESTAMP)
    s.begin_date_time                                  AS begin_datetime,
    s.end_date_time                                    AS end_datetime,

    -- measures (Power BI type contract)
    CAST(COALESCE(s.injuries_direct, 0) + COALESCE(s.injuries_indirect, 0) AS INT) AS injuries_total,
    CAST(COALESCE(s.deaths_direct, 0)   + COALESCE(s.deaths_indirect, 0)   AS INT) AS deaths_total,
    CAST(s.damage_property_usd AS NUMBER(18,2))            AS damage_property_usd,
    CAST(s.damage_crops_usd    AS NUMBER(18,2))            AS damage_crops_usd,
    CAST(s.damage_property_usd + s.damage_crops_usd AS NUMBER(18,2)) AS financial_impact_usd,
    1                                                      AS event_count,

    -- composite risk (Q9): $ damage + injuries + deaths
    -- weights: 1 injury = $100k, 1 death = $1M (documented defaults, tunable)
    CAST(
        s.damage_property_usd + s.damage_crops_usd
        + COALESCE(s.injuries_direct, 0) * 100000
        + COALESCE(s.injuries_indirect, 0) * 100000
        + COALESCE(s.deaths_direct, 0) * 1000000
        + COALESCE(s.deaths_indirect, 0) * 1000000
        AS NUMBER(18,2)
    )                                                      AS severity_risk_score,

    -- flags (BOOLEAN)
    (s.event_type = 'Tornado')                             AS is_tornado,
    (s.event_type IN ('Flood', 'Flash Flood', 'Coastal Flood',
                      'Lakeshore Flood', 'Storm Surge/Tide')) AS is_flood,
    s.is_test_event

FROM silver s
JOIN us_states st ON st.state_name = s.state
