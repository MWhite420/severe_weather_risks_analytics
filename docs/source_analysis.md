# NOAA Storm Events - 2022 Source Inspection

## 1. Source Overview

The 2022 NOAA Storm Events Details file was inspected to understand the source data before designing the Snowflake pipeline.

- **Source:** NOAA Storm Events Details
- **Year:** 2022
- **Records:** 69,887
- **Columns:** 51
- **Event Types:** 53

Each record represents a reported storm or severe-weather event.

---

## 2. Data Quality Findings

| Check | Result |
|---|---:|
| Missing `STATE` | 0 |
| Missing `EVENT_TYPE` | 0 |
| Duplicate `EVENT_ID` | 0 |
| Missing `DAMAGE_PROPERTY` | 16,391 |
| Missing `DAMAGE_CROPS` | 15,808 |

No missing state or event-type values were found.

No duplicate `EVENT_ID` values were found within the 2022 file.

---

## 3. Event Types

The dataset contains **53 different event types**.

The most frequent event types in 2022 were:

| Event Type | Events |
|---|---:|
| Thunderstorm Wind | 17,595 |
| Hail | 7,180 |
| Drought | 6,873 |
| High Wind | 5,179 |
| Winter Weather | 4,762 |

`EVENT_TYPE` will be used for event frequency and event-impact analysis.

---

## 4. Damage Data

Property and crop damage are stored as strings rather than numeric values.

Examples include:

- `0.00K`
- `1.00K`
- `100.00K`
- `500.00K`
- `1.00M`
- `2.00M`

The suffixes represent:

- `K` = thousands
- `M` = millions
- `B` = billions

The source contains both explicit zero values and missing values.

For example:

- `0.00K` represents zero reported damage.
- `NULL` represents a missing damage value.

Missing damage values should therefore not automatically be treated as zero.

---

## 5. Date Data

The `BEGIN_DATE_TIME` field is stored as a string.

The dates were successfully parsed using the expected date format, with **0 invalid dates** identified.

The 2022 data contains records covering the full calendar year:

**January 1, 2022 00:00:00 - December 31, 2022 23:30:00.**

All 12 months are represented in the dataset.

The months with the highest number of events were:

| Month | Events |
|---|---:|
| July | 9,189 |
| June | 8,940 |
| May | 8,460 |
| December | 6,899 |
| April | 6,164 |

---

## 6. Important Fields

The following fields were identified as important for the business requirements:

- `EVENT_ID`
- `EPISODE_ID`
- `STATE`
- `STATE_FIPS`
- `YEAR`
- `MONTH_NAME`
- `BEGIN_DATE_TIME`
- `END_DATE_TIME`
- `EVENT_TYPE`
- `DAMAGE_PROPERTY`
- `DAMAGE_CROPS`
- `MAGNITUDE`
- `MAGNITUDE_TYPE`
- `INJURIES_DIRECT`
- `INJURIES_INDIRECT`
- `DEATHS_DIRECT`
- `DEATHS_INDIRECT`
- `TOR_F_SCALE`

The remaining source fields will be evaluated during the cleaning and reporting stages.


## 7. Initial Observations

Inspection identified several areas that will require attention during the Snowflake cleaning process:

- Damage values need to be converted from strings into numeric values.
- Missing damage values need to remain distinguishable from reported zero damage.
- Date fields need to be stored as appropriate timestamp values.
- Event and state information can be used for reporting and aggregation.
- `EVENT_ID` had no duplicates within the 2022 source file.
- The same inspection process will be performed on the 2023 and 2024 files before finalizing the pipeline.

---