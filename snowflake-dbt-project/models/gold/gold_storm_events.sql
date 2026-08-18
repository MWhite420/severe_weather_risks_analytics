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
-- =========================================================

WITH silver AS (
    SELECT * FROM {{ ref('silver_storm_events') }}
),

-- 13 marine/offshore zones (validated live: 10,954 rows, 3.8%)
-- These are NOT map-able to a US state in Power BI.
marine_zones AS (
    SELECT column1 AS zone_name FROM VALUES
        ('ATLANTIC NORTH'),
        ('ATLANTIC SOUTH'),
        ('E PACIFIC'),
        ('GUAM WATERS'),
        ('GULF OF ALASKA'),
        ('GULF OF MEXICO'),
        ('LAKE ERIE'),
        ('LAKE HURON'),
        ('LAKE MICHIGAN'),
        ('LAKE ONTARIO'),
        ('LAKE ST CLAIR'),
        ('LAKE SUPERIOR'),
        ('ST LAWRENCE R')
)

SELECT
    -- identity / grain
    s.event_id,

    -- dimensions
    s.state,
    CASE WHEN mz.zone_name IS NOT NULL THEN 'MARINE' ELSE 'STATE' END AS state_type,
    s.year,
    MONTH(s.begin_date_time)                               AS month,
    TO_CHAR(s.begin_date_time, 'FMMonth')                  AS month_name,
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
LEFT JOIN marine_zones mz ON mz.zone_name = s.state
