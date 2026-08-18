                         NOAA
                   Storm Event Files
                 2022 | 2023 | 2024
                         |
                         v
                 +---------------+
                 | Landing Area  |
                 | Source Files  |
                 +---------------+
                         |
                         v
                 +---------------+
                 | Snowflake     |
                 | Stage         |
                 +---------------+
                         |
                         v
                 +---------------+
                 | RAW           |
                 | Source Data   |
                 | + Metadata    |
                 +---------------+
                         |
                         v
                 +---------------+
                 | CLEAN         |
                 | Validated     |
                 | Standardized  |
                 +---------------+
                         |
                         v
                 +---------------+
                 | REPORTING     |
                 | Business Data |
                 +---------------+
                         |
                         v
                    Power BI


LATER FOR INCREMENTAL PROCESSING...


                         2025
                          |
                          v
                    New Arrival
                          |
                          v
                       Stage
                          |
                          v
                 Process New Data
                          |
                          v
                    RAW → CLEAN
                          |
                          v
                      REPORTING
                          |
                          v
                      Power BI