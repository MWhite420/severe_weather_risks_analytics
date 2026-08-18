### 🟤 BRONZE — raw intake (done)
**Purpose:** land the CSV files into Snowflake exactly as-is — the immutable source of truth.
**Source → destination:** 4 CSVs on stage → `DBT_DB.RAW.*` tables.
**Transformations:** none — all 51 columns kept as-is, all `VARCHAR`; just `COPY INTO` (skip header, quoted fields handled).
**Dropped:** nothing — the raw layer keeps everything.
**dbt models → views:** `models/bronze/bronze_storm_events_2022.sql` … `_2025.sql` — one raw per-year view per source table (each just `SELECT *`). **No union in Bronze** — the union happens in Silver.

| Table | Rows |
|-------|------|
| `RAW.STORM_EVENTS_2022` | 69,887 |
| `RAW.STORM_EVENTS_2023` | 75,593 |
| `RAW.STORM_EVENTS_2024` | 69,801 |
| `RAW.STORM_EVENTS_2025` | 72,360 |

### ⚪ SILVER — clean & typed (next to build)
**Purpose:** one clean, typed, deduplicated dataset free of junk — the reusable core for all analysis.
**Source → destination:** Bronze → `SILVER.SILVER_STORM_EVENTS`.
**Transformations:**
- Union all 4 years into one table; primary key = `EVENT_ID` (no duplicates today, dedup if any appear).
- Cast `BEGIN_DATE_TIME` / `END_DATE_TIME` → `TIMESTAMP` using the confirmed format `DD-MON-YY HH24:MI:SS`.
- Cast `INJURIES_DIRECT/INDIRECT`, `DEATHS_DIRECT/INDIRECT` → integer.
- Convert damage strings `K/M/B` → numeric USD; treat `0`, `0.00K`, and NULL as `$0`.
- Flag test data: `is_test_event = TRUE` for the 256 rows whose `EVENT_ID` starts with `999` (decision: keep-vs-drop still open).

**Dropped (junk / redundant / too-sparse columns):**
- Constant / no value: `DATA_SOURCE` (always `CSV`), `CATEGORY`, `CZ_TYPE`, `STATE_FIPS`.
- Redundant with a kept column: `BEGIN_YEARMONTH/BEGIN_DAY/BEGIN_TIME` and `END_YEARMONTH/END_DAY/END_TIME` (already in the datetimes), `MONTH_NAME` (derivable).
- Too sparse / event-specific: `MAGNITUDE_TYPE`, `MAGNITUDE`, `FLOOD_CAUSE`, all `TOR_*` columns, `BEGIN_RANGE/AZIMUTH/LOCATION`, `END_RANGE/AZIMUTH/LOCATION`.

**Kept & cleaned:** `EVENT_ID`, `STATE`, `YEAR`, `EVENT_TYPE`, `CZ_FIPS`, `CZ_NAME`, `WFO`, `BEGIN_DATE_TIME`, `END_DATE_TIME`, `INJURIES_DIRECT/INDIRECT`, `DEATHS_DIRECT/INDIRECT`, `DAMAGE_PROPERTY`, `DAMAGE_CROPS`, `SOURCE`, `BEGIN_LAT/LON`, `END_LAT/LON`, plus the narratives (`EPISODE_NARRATIVE`, `EVENT_NARRATIVE`).

**Table name:** `SILVER.SILVER_STORM_EVENTS`.

### 🟡 GOLD — Power BI-ready mart (next to build)
**Purpose:** a single analytics table (one row per event) shaped so Power BI can answer all 10 dashboard questions directly, with correct types.
**Source → destination:** `SILVER.SILVER_STORM_EVENTS` → `GOLD.GOLD_STORM_EVENTS` (grain = one row per `EVENT_ID`).
**Transformations:**
- Dimensions: `state`, `state_type`, `state_abbr` (optional), `year`, `month`, `month_name`, `event_type`, `cz_name`, `cz_fips`, `wfo`, `begin_datetime`, `end_datetime`.
- Measures: `event_count` (always 1), `injuries_total`, `deaths_total`, `damage_property_usd`, `damage_crops_usd`, `financial_impact_usd`, `severity_risk_score`.
- `financial_impact_usd = damage_property_usd + damage_crops_usd`.
- `severity_risk_score` = composite of damage + injuries + deaths (weights pending).
- `state_type` = `'STATE'` for real US states/territories, `'MARINE'` for offshore zones (lakes/gulfs/oceans — not map-able to a US state).
- Enforce the **Power BI type contract**: `TIMESTAMP` for dates, `NUMBER(18,2)` for money, `INT` for counts, `BOOLEAN` for flags, `VARCHAR` for dimensions; no text `NULL` or empty strings in numeric/date columns.

**Table name:** `GOLD.GOLD_STORM_EVENTS`. Optional small dim tables (`GOLD.DIM_STATE`, `GOLD.DIM_EVENT_TYPE`) if a star schema is preferred — not required for Power BI.

### 🔵 POWER BI (last step)
**Source:** connects (read-only) to `GOLD.GOLD_STORM_EVENTS`.
**Shows (dashboard):** year slicer (2022–2025) · state map · event-type bar · damage-by-state bar · monthly severity trend · risk ranking. Together these visuals answer all 10 questions from the single fact table.
