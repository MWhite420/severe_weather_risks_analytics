-- =========================================================
-- BRONZE: bronze_storm_events_2025
-- ---------------------------------------------------------
-- Per-year raw view. Bronze = raw, immutable, un-transformed
-- (all columns kept, all VARCHAR as loaded from CSV).
-- NO union here — Silver unions the 4 years and cleans/types.
-- =========================================================

SELECT *
FROM {{ source('raw_storm', 'STORM_EVENTS_2025') }}
