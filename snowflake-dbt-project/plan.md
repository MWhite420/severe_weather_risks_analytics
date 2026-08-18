# Plan — Storm Events dbt Project on Snowflake (Medallion Architecture)

> Goal: get the NOAA Storm Events CSVs (2022–2025) into Snowflake and build a **medallion-architecture** dbt project on top of them.
> **No uploads / no execution in Snowflake from this file** — this is planning only for Master + OpenClaw to agree on steps.

---

## 1. Current state

### Local workspace — `/root/.openclaw/workspace/home/snowflake-dbt-project/`
- `seeds/` → 4 source CSVs (NOAA Storm Events, one per year): `StormEvents_details-ftp_v1.0_d2022_c20260625.csv` …`_d2025_c20260728.csv`
- `dbt_project.yml` (name/profile: `snowflake_dbt_project`)
- `profiles.yml` (connection — gitignored, has creds)
- `models/` → placeholder `staging/stg_example.sql`, `marts/mart_example.sql`, `schema.yml`
- `.snowflake/config.toml` (snow CLI config — gitignored)
- `.gitignore`, `plan.md`

### Snowflake account (`ieygdkm-tf08540`)
- Database created by us: **`DBT_DB`** — schema `RAW`, stage `storm_stage` → contains the 4 CSVs (uploaded, not loaded). No tables loaded yet.
- **Weather project** = a Snowsight **Workspace** stored in Snowflake: `snow://workspace/USER$DEMOMAN12568.PUBLIC.DEFAULT$/versions/live/Weather/` (dbt project with `models/`, `seeds/`, etc.). Accessible read/write via SQL (`LS`/`GET`/`PUT`).
- **Bronze dbt files added to the Weather workspace** (done): `models/bronze/sources.yml`, `models/bronze/bronze_storm_events_2022..2025.sql` (per-year raw views, no union), `macros/generate_schema_name.sql` (so `+schema: bronze` → `BRONZE`, not `RAW_BRONZE`), and `dbt_project.yml` updated with bronze config.

### Tooling (on this host)
- Snowflake CLI `snow` 3.24.1, dbt-core 1.12.2 + dbt-snowflake 1.12.0 (both in isolated venvs)

### Key facts / constraints
- Files are on **stage**, not tables — can't `SELECT` a stage directly.
- `LIST` / `LAST_QUERY_ID()` / `RESULT_SCAN()` don't work in dbt SQL models.
- 51 columns; quoted narratives contain commas/newlines → need proper CSV parsing on load.
- Master works in a **web-UI "workspaces"/dbt project** layer, separate from the database layer I query.

---

## 2. Target architecture — Medallion (Bronze → Silver → Gold)

```
stage (storm_stage)  ──load──▶  BRONZE  ──clean/drop──▶  SILVER  ──aggregate──▶  GOLD
  4 x CSV files               raw as loaded              typed + cleaned           business-ready
  51 cols, untyped            all VARCHAR                 ~clean subset             marts/analytics
```

- **Bronze** (schema `BRONZE`): raw copy off stage, line-for-line, all-VARCHAR. One table per year: `STORM_EVENTS_2022..2025`. Immutable source of truth.
- **Silver** (schema `SILVER`): dbt staging — union years, **drop junk** (see §2.1), type + standardize → one clean `SILVER_STORM_EVENTS` table.
- **Gold** (schema `GOLD`): dbt marts — Power-BI-ready fact/dimension tables at event grain, designed so Power BI can build the target visualizations (see §2.2).

### 2.1 JUNK-DATA DROP LIST (for the Silver layer)
_From profiling all 287,641 rows across the 4 files. Each item = what to drop/clean in Silver._

#### (a) Columns that are wholly junk / carry no signal → DROP entirely
| Column | Why dropped (evidence) |
|--------|------------------------|
| **DATA_SOURCE** | 100% constant `'CSV'` for every row — no information. |
| **CATEGORY** | ~100% empty (287,526/287,641 blank); the few non-blank values (74/26/7/8) are not a real shared category — effectively junk. Drop (or re-evaluate separately). |
| **CZ_TYPE** | Only 2 values (`C`/`Z`); duplicated in essence by whether a storm is a county/zone event — low/no analytical value as-is. Keep only if needed for CZ semantics (see note). |
| **BEGIN_YEARMONTH / BEGIN_DAY / BEGIN_TIME** | Fully redundant — same info is in `BEGIN_DATE_TIME` (`DD-MON-YY HH:MM:SS`). Drop the 3 split fields, keep `BEGIN_DATE_TIME`. |
| **END_YEARMONTH / END_DAY / END_TIME** | Same — fully redundant with `END_DATE_TIME`. Drop the 3 split fields. |
| **MONTH_NAME** | Fully derivable from `BEGIN_DATE_TIME` (or `YEAR`+date). Redundant. Drop. |
| **STATE_FIPS** | Duplicates `STATE` (one-to-one FIPS↔state abbreviation: 68↔68). Drop (keep `STATE`). |
| **MAGNITUDE_TYPE** | 61% empty; the few types (EG/MG/MS/ES) only apply to wind events. Can be kept as-is or dropped; recommend **parsing into a clean `MAGNITUDE`** instead. See note. |

#### (b) Columns that are mostly empty / sparse → DROP, or keep only for tornado events
| Column | Empty % | Recommendation |
|--------|---------|----------------|
| **FLOOD_CAUSE** | 90.6% empty | Only set for flood event types. Drop from main table OR keep in a flood-specific sub-table. |
| **TOR_F_SCALE** | 97.7% empty | Tornado-only. Split into a tornado detail table, or keep nullable. |
| **TOR_LENGTH** | 97.7% empty | Tornado-only. Same treatment. |
| **TOR_WIDTH** | 97.7% empty | Tornado-only. Same treatment. |
| **TOR_OTHER_WFO** | 99.6% empty | Tornado-only, rarely populated. Drop / tornado-detail only. |
| **TOR_OTHER_CZ_STATE** | 99.6% empty | Tornado-only. Drop / tornado-detail only. |
| **TOR_OTHER_CZ_FIPS** | 99.6% empty | Tornado-only. Drop / tornado-detail only. |
| **TOR_OTHER_CZ_NAME** | 99.6% empty | Tornado-only. Drop / tornado-detail only. |
| **MAGNITUDE** | 48% empty | Only set for wind events (High Wind, Thunderstorm Wind, etc.). Keep nullable or wind-detail only. |
| **BEGIN_RANGE / END_RANGE** | 41.8% empty | Location detail; merge into location handling. Keep nullable or drop. |
| **BEGIN_AZIMUTH / END_AZIMUTH** | 41.8% empty | Location detail (compass dir, e.g. `N`,`NE`). Keep nullable or drop. |
| **BEGIN_LOCATION / END_LOCATION** | 41.8% empty | Place names — keep nullable (may be useful) or drop. |

#### (c) Columns that are NOT junk — KEEP (for reference)
`EPISODE_ID`, `EVENT_ID` (unique PK, 287,641 distinct), `STATE`, `YEAR`, `EVENT_TYPE`, `CZ_FIPS`, `CZ_NAME`, `WFO`, `BEGIN_DATE_TIME`, `END_DATE_TIME`, `CZ_TIMEZONE`, `INJURIES_DIRECT/INDIRECT`, `DEATHS_DIRECT/INDIRECT`, `DAMAGE_PROPERTY`, `DAMAGE_CROPS`, `SOURCE`, `BEGIN_LAT/LON`, `END_LAT/LON`, `EPISODE_NARRATIVE`, `EVENT_NARRATIVE`.

#### (d) Value-level junk inside kept columns → DROP/CLEAN rows or normalize
| Item | Evidence / treatment |
|------|----------------------|
| **DAMAGE_PROPERTY / DAMAGE_CROPS = `0.00K`** | 22.8% / 23.2% of rows are the placeholder `0.00K` (= no damage, but the `K` means the token represents thousands). **Parse** `0.00K`→0; parse `1.00K`→1000, `0.50M`→500000, etc. into a numeric `dmg_amount` + `dmg_unit`/`is_zero` flag. |
| **Damage fields with literal `0` / `0.00`** | Non-standard tokens appear (e.g. `0`, `0.00M`, `0.01K`); normalize all to numeric amounts. |
| **Injuries/Deaths values** | All clean digits (`0`,`1`,`2`…) — keep, cast to INTEGER. **No junk found.** |
| **EVENT_ID starting `999`** | 256 test/placeholder-like IDs (`999902`…) — flag/note them; decide keep-vs-drop (likely drop or mark `is_test_event`). |
| **DATE fields (`BEGIN_DATE_TIME`/`END_DATE_TIME`)** | Parse `DD-MON-YY HH:MM:SS` (e.g. `20-FEB-22 21:18:00`) → proper TIMESTAMP. Standardize timezone handling. |
| **CZ_TIMEZONE** | 12 timezone strings (`CST-6`, `EST-5`, `MST-7`, `PST-8`, `AST-4`…) — normalize to a standard offset/tz name. |
| **Narrative fields** | Some narratives are boilerplate placeholders (e.g. `"MPing report."`, `"The report was relayed through mPING."`, repeated heat-index lines, repeated ridge text ×885) — keep (they're legitimate reports) but note many are templated. Do **not** drop whole rows; could flag `is_template_narrative` if desired. |
| **Row-level null handling** | Tornado/location/damage empties represent *absence* of that attribute, not corrupt rows — **drop columns, don't drop rows** (except duplicate EVENT_IDs if any after dedup — currently all distinct). |

#### (e) Dedup / identity
- `EVENT_ID` is unique across all 4 files (287,641 distinct) → serves as the Silver **primary key**. Ensure `not_null` + `unique` tests; drop any duplicated `EVENT_ID` rows if they ever appear.

### 2.2 GOLD LAYER — Power BI-ready mart (event grain)
_Designed from Master's 10 Power BI questions so the Gold tables can answer them directly._

**Core design principle:** one row per storm event (grain = `EVENT_ID`), with cleaned dimensions + numeric measures. Power BI aggregates from a single fact table — no per-chart SQL needed.

**Gold table: `GOLD.GOLD_STORM_EVENTS`** (materialized table, event grain)
| Column | Type | Purpose (which Q it answers) |
|--------|------|------------------------------|
| `event_id` (PK) | VARCHAR | identity / row grain |
| `state` | VARCHAR | Q1, Q3, Q4, Q8, Q9 (full name, e.g. `ALABAMA`) |
| `state_abbr` | VARCHAR (optional) | 2-letter abbrev via mapping |
| `state_type` | VARCHAR | `'STATE'` vs `'MARINE'` (marine zones not map-able) |
| `state_region` | VARCHAR (optional) | region rollups (nice-to-have) |
| `year` | INT | Q7, Q10 (2022 vs 2023 vs 2024; 2025 filter) |
| `month` | INT | Q6 (monthly severity seasonality) |
| `month_name` | VARCHAR | Q6 display |
| `event_type` | VARCHAR | Q2, Q5, Q8 |
| `cz_name`, `cz_fips`, `wfo` | VARCHAR | drill-down detail |
| `begin_datetime`, `end_datetime` | TIMESTAMP | time filtering / drill |
| `injuries_total` | INT | Q9 risk (part of score) |
| `deaths_total` | INT | Q9 risk (part of score) |
| `damage_property_usd` | NUMBER | Q3, Q5, Q9 |
| `damage_crops_usd` | NUMBER | Q4, Q5, Q9 |
| `financial_impact_usd` | NUMBER | Q5 (property + crops) |
| `event_count` | INT | Q1, Q2, Q6, Q7, Q8, Q10 (always 1) |
| `severity_risk_score` | NUMBER | Q9 (composite risk) |
| `is_tornado` / `is_flood` | BOOLEAN | optional filters |

**_Power BI TYPE CONTRACT (what Power BI needs to build the visuals):_**
Power BI maps Snowflake types to model types — get these wrong and slicers/filters/sums break. Gold will expose:

| Power BI model type | Gold columns | Snowflake type | Why it matters |
|---------------------|--------------|----------------|----------------|
| **Date/Time** | `begin_datetime`, `end_datetime` | `TIMESTAMP` | Enables date hierarchy (year/quarter/month) + time-intelligence; must NOT be VARCHAR (text dates can't filter/slice) |
| **Integer** | `year`, `month`, `event_count`, `injuries_total`, `deaths_total` | `NUMBER(38,0)` / `INT` | Correct count/sum aggregation |
| **Decimal / Currency** | `damage_property_usd`, `damage_crops_usd`, `financial_impact_usd`, `severity_risk_score` | `NUMBER(18,2)` (risk: `NUMBER(18,2)` — see fix note in Phase 3) | Money must SUM; Power BI formats $ client-side; never send as VARCHAR |
| **Text** (dimensions/slicers) | `state`, `state_type`, `month_name`, `event_type`, `cz_name`, `cz_fips`, `wfo` | `VARCHAR` | Slicers, axes, legends, row labels |
| **TRUE/FALSE** | `is_tornado`, `is_flood` | `BOOLEAN` | Clean Yes/No filters |

**Rules for clean import:**
- **No text `"NULL"` / empty strings in numeric/date columns** — use real SQL NULL so Power BI shows blanks (sums ignore them correctly).
- `year`/`month` as separate Integer columns (in addition to `begin_datetime`) so Power BI has a clean axis + hierarchy without parsing.
- Money columns are plain decimals; apply currency format in Power BI ($) — no special Snowflake type needed.
- Single denormalized fact (event grain) = auto type-detection, no joins → fewest type/discovery problems in Power BI.


**_Damage parsing into USD (Silver→Gold):_** `DAMAGE_PROPERTY`/`DAMAGE_CROPS` are strings like `1.00K`, `0.50M`, `0`, `0.00K`, or **NULL**. Validated distribution (287,641 rows): `0.00K`=58.5%, NULL=22.8%, real K/M/B=18.7%, other zero-forms (`0`,`0.00`,`0K`)=0.04%.
- NULL / `0.00K` / `0` / `0.00` / `0K` → `0` (≈81% of rows = no damage)
- `K` suffix → ×1,000 · `M` suffix → ×1,000,000 · **`B` suffix → ×1,000,000,000** (12 rows have `B`)
- Store clean numerics `damage_property_usd`, `damage_crops_usd`; derive `financial_impact_usd = property + crops`.

**_State handling (validated — IMPORTANT):_** `STATE` holds **full state NAMES** (`ALABAMA`, `TEXAS`), not 2-letter codes (66 distinct incl. territories AMERICAN SAMOA, GUAM, PUERTO RICO, VIRGIN ISLANDS, DISTRICT OF COLUMBIA) **plus 13 marine/offshore zones** (`GULF OF MEXICO`, `LAKE ERIE`, `ATLANTIC NORTH`, `ATLANTIC SOUTH`, `E PACIFIC`, `GUAM WATERS`, `GULF OF ALASKA`, `LAKE MICHIGAN`, `LAKE ONTARIO`, `LAKE HURON`, `LAKE ST CLAIR`, `LAKE SUPERIOR`, `ST LAWRENCE R`) = 10,954 rows (3.8%).
- Add `state_type` flag: `'STATE'` vs `'MARINE'` (marine zones won't map to a US state map in Power BI).
- Keep `state` as full name (maps by name in Power BI); optionally add `state_abbr` via a mapping table.

**_Geography note (lat/lon):_** `BEGIN_LAT/LON` are clean numerics but **22% are NULL** (64,179 rows) — fine for state-level analysis; only usable for point-maps when present.

**_Risk score (Q9):_** composite `severity_risk_score` per event, e.g.
`risk = damage_property_usd + damage_crops_usd + (injuries_total * X) + (deaths_total * Y)`, normalized per state for the “highest weather-related risk” ranking. **Defaults implemented (tunable): X = 100,000 (1 injury ≈ $100k), Y = 1,000,000 (1 death ≈ $1M).** Risk stored as `NUMBER(18,2)`.

**_Year handling (Q10):_** keep `year` as a regular dimension (do NOT hardcode 2022–2024). `2025` rows already in the source → when refreshes happen, 2025 automatically shows as a filterable period in Power BI (Q10).

**(Optional) small dim tables if a true star schema is preferred:**
- `GOLD.DIM_STATE` (`state`, `state_name`, `region`) — if state rollups/attributes are wanted.
- `GOLD.DIM_EVENT_TYPE` (`event_type`, `category`) — if event-type hierarchies are wanted.

**VALIDATION — design confirmed against live data (2026-08-18):**
| Check | Result | Implication |
|-------|--------|-------------|
| Date parse `DD-MON-YY HH24:MI:SS` | 100% (287,641 rows) | Must use explicit format; auto-detect fails |
| Year col vs parsed date | 0 mismatches | `month`/`year` derivable from `BEGIN_DATE_TIME` |
| EVENT_ID uniqueness | 287,641 distinct = rows | Clean PK, no dedup needed |
| Damage tokens | K (220k), M (1.4k), B (12), 0.00K (168k), NULL (65k), zeros (119) | Parse K/M/B; ~81% = $0 |
| STATE | 66 names incl. 13 marine zones (10,954 rows) | Need `state_type` flag (validated: 13 zones, full list in §2.2) |
| Injuries/deaths | 0 bad, all numeric | cast to int |
| event_type | 53 distinct (top: Thunderstorm Wind) | dimension OK |
| lat/lon | 0 bad, but 22% NULL | state-level OK; point-maps limited |

### 2.3 Power BI — what each question SHOULD show
_Mapping Master's 10 questions → visualization design (built from `GOLD.GOLD_STORM_EVENTS`)._

| # | Question | Power BI visual to show |
|---|----------|--------------------------|
| 1 | Which states have the highest number of storm events? | **Bar / map**: count of `event_id` per `state` (top-N states). Choropleth map of states colored by event count. |
| 2 | Which storm events occur most frequently? | **Bar chart**: count of `event_id` grouped by `event_type` (sorted desc). |
| 3 | Which states experience the highest property damage? | **Bar / map**: `SUM(damage_property_usd)` per `state`. Choropleth by damage tier. |
| 4 | Which states experience the highest crop damage? | **Bar / map**: `SUM(damage_crops_usd)` per `state`. |
| 5 | Which types of events create the greatest financial impact? | **Bar**: `SUM(financial_impact_usd)` (=property+crops) per `event_type`, sorted desc. Optionally stacked property vs crops. |
| 6 | Which months experience more severe-weather activity? | **Line/column**: count of events by `month` (1–12). Optionally a **heatmap** month×year. |
| 7 | How does storm activity change between 2022, 2023 and 2024? | **Column/line over time**: event count by `year` (2022/2023/2024). Growth % change. Slicer on `year`. |
| 8 | Are particular storm types more common in certain states? | **Heatmap / matrix**: rows = `state`, columns = `event_type` (or vice versa), values = event count. Or stacked bar per state by event type. |
| 9 | Which states appear to have the highest overall weather-related risk? | **Ranking/bar + map**: `SUM(severity_risk_score)` (or aggregated risk) per `state`, top-N. Risk level gauge/category. |
| 10 | What changes when the 2025 data becomes available? | **Year slicer/filter** on all charts (`year` incl. 2025); period-over-period comparisons (2024 vs 2025); trend lines. 2025 flows in automatically since `year` is a dimension. |

**Recommended Power BI layout:** a dashboard with a **year slicer (2022–2025)** + **state map** + **event-type bar** + **damage-by-state bar** + **monthly trend line** + **risk ranking**, all from `GOLD.GOLD_STORM_EVENTS`. Drill from state → event type → month.

**Connection:** Power BI → Snowflake (connector) → `DBT_DB.GOLD.GOLD_STORM_EVENTS`. Provide a read-only role/query for Power BI (open question, §3).

---

## 3. Open questions for Master
1. **Database** — keep `DBT_DB`? 
2. **Bronze** — confirm load into `BRONZE.STORM_EVENTS_2022..2025` (per-year) and keeping files on stage.
3. **Tornado fields** — separate `TORNADO` detail table vs. nullable columns in Silver?
4. **Flood fields** — separate `FLOOD_EVENT` detail vs. main table?
5. **Event-ID `999…` rows** — drop or flag (`is_test_event`)?
6. **Gold scope — now DEFINED by Power BI questions** (see §2.2/§2.3). Open sub-decisions:
   - Risk score weights (severity_risk_score formula) — propose defaults and confirm.
   - Include optional `DIM_STATE` / `DIM_EVENT_TYPE` dim tables, or single fact only? (Recommend single fact to start.)
   - Power BI read access: create a read-only role/grant for the Power BI connector vs. reuse ACCOUNTADMIN?
7. **Silver materialization** — table (recommend) vs. view/incremental.

---

## 4. Proposed plan (in order) — NO Snowflake changes until Master approves

### Phase 0 — Agree destination + architecture (this doc)
### Phase 1 — Bronze layer
**STATUS: ✅ DONE (files written AND raw tables loaded)**

**Bronze dbt files written into Weather workspace** (`snow://workspace/…/Weather/`):
- `models/bronze/sources.yml` — declares the 4 raw source tables (`DBT_DB.RAW.STORM_EVENTS_2022..2025`) as dbt sources.
- `models/bronze/bronze_storm_events_2022.sql` … `_2025.sql` — one raw per-year view per source (**no union**; Silver does the union).
- `macros/generate_schema_name.sql` — overrides dbt's default schema naming so `+schema: bronze` resolves to `BRONZE` (not `RAW_BRONZE`).
- `dbt_project.yml` — added bronze model config (`+schema: bronze`, `+materialized: view`).

**Raw tables loaded (done, Master-approved):**
- `DBT_DB.RAW.STORM_EVENTS_2022` (69,887) · 2023 (75,593) · 2024 (69,801) · 2025 (72,360) = **287,641 rows total, 0 errors** (`COPY INTO`, SKIP_HEADER=1, FIELD_OPTIONALLY_ENCLOSED_BY='"').
- CSVs still on stage `@DBT_DB.RAW.storm_stage` + local `seeds/` (not deleted).
- Per-year bronze views validated against live data (each `SELECT *` runs clean).
- **Snowflake fixed (Master-approved):** dropped the unified union view `RAW_BRONZE.BRONZE_STORM_EVENTS`, dropped the `RAW_BRONZE` schema, created clean `BRONZE` schema with the 4 per-year raw views.
- **Workspace synced:** removed old `bronze_storm_events.sql` + stale `target/` artifacts; uploaded the 4 per-year views to `models/bronze/` and `macros/generate_schema_name.sql`.
- **Remaining (optional):** run `dbt run` to materialize the 4 `bronze.bronze_storm_events_YYYY` views.
### Phase 2 — Silver (models/silver) — apply §2.1 drop list
**STATUS: ✅ DONE (files written + model validated against live data)**
- `models/silver/schema.yml` → silver model + tests (not_null/unique on `event_id`, accepted values on `year`).
- `models/silver/silver_storm_events.sql`: union 4 bronze year views, drop junk cols (§2.1a–b), parse damage K/M/B → USD via `parse_damage_usd` macro (§2.1d), cast dates → TIMESTAMP + counts → INT + lat/lon → NUMBER, flag `is_test_event` for `999…` IDs, PK = `EVENT_ID`.
- `macros/parse_damage_usd.sql` added. `dbt_project.yml` `silver: +schema: silver, +materialized: table` (folder `models/silver` mirrors `models/bronze`).
- **Model validated live:** 287,641 rows · 287,641 distinct EVENT_ID (0 null) · 0 bad dates · 256 test events flagged · K/M/B damage parse correct.
- Output `SILVER.SILVER_STORM_EVENTS` (model `silver_storm_events` in `models/silver`, config `schema: silver` → `SILVER`).
### Phase 3 — Gold (models/gold) — Power-BI-ready event-grain fact table
**STATUS: ✅ DONE (files written + model validated against live data)**
- `models/gold/gold_storm_events.sql`: builds `GOLD.GOLD_STORM_EVENTS` from `ref('silver_storm_events')`.
  - Event grain (`EVENT_ID` PK).
  - Dimensions: `state`, `state_type`, `year`, `month`, `month_name`, `event_type`, `cz_name`, `cz_fips`, `wfo`, `begin_datetime`, `end_datetime`. (`state_abbr`/`state_region` optional — skipped for now.)
  - Measures: `event_count` (always 1), `injuries_total`, `deaths_total`, `damage_property_usd`, `damage_crops_usd`, `financial_impact_usd`, `severity_risk_score`.
  - `severity_risk_score` formula (defaults, tunable): `damage_property_usd + damage_crops_usd + injuries_total*100000 + deaths_total*1000000` (1 injury ≈ $100k, 1 death ≈ $1M).
  - `state_type` = `'STATE'` / `'MARINE'` via explicit 13-zone list (validated live: 10,954 marine rows). `is_tornado`/`is_flood` flags. `year` as dimension (for Q10).
- **Type contract fix:** `severity_risk_score` is **NUMBER(18,2)**, NOT NUMBER(10,4) — max damage is $7B (B tokens), which overflows NUMBER(10,4).
- `schema.yml` tests: uniqueness/not-null on `event_id`, relationships to Silver (`ref('silver_storm_events')`), accepted values on `state_type`/`year`/`month`.
- **Model validated live (full bronze→silver→gold chain):** 287,641 rows · 287,641 distinct EVENT_ID (0 null) · MARINE 10,954 / STATE 276,687 · 0 null state_type/month/begin_datetime/injuries/deaths · max financial $7,000,000,000 · max risk $7,060,000,000 (fits NUMBER(18,2)) · years 2022–2025.
### Phase 3b — Power BI
- Connect Power BI to `DBT_DB.GOLD.GOLD_STORM_EVENTS`; build visuals per §2.3 table; add year slicer + state map + damage/risk rankings.
### Phase 4 — Verify — `dbt debug`, `dbt run`, `dbt test`; confirm web-UI dbt project sees the tables.

---

## 5. Tooling / commands reference
- `snow connection test` · `snow sql -q "LIST @DBT_DB.RAW.storm_stage;"` · `snow stage copy <file> @DBT_DB.RAW.storm_stage --overwrite`
- `dbt debug --profiles-dir .` · `dbt run` · `dbt test`

---

## 6. Explicitly NOT doing (per Master)
- **No uploads / no Snowflake changes** until Master approves (this file is planning only).
- `plan.md` is local only — not uploaded to Snowflake.

---

## 7. LAYER-BY-LAYER SUMMARY (quick read, no cross-references)

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

**End-to-end flow:**
```
4 CSVs (stage) ─▶ RAW.STORM_EVENTS_2022..2025  ─▶ SILVER.SILVER_STORM_EVENTS  ─▶ GOLD.GOLD_STORM_EVENTS  ─▶ Power BI
   (Bronze)          raw, 51 cols, VARCHAR            clean + typed            Power-BI mart            dashboards
```
