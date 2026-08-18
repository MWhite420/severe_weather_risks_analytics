SELECT
    "name" AS stage_path,
    "size" AS file_size_bytes,
    ROUND("size" / 1024 / 1024, 2) AS file_size_mb,
    "md5",
    "last_modified"
FROM TABLE STORM_STAGEDBT_DB.RAW.STORM_STAGEDBT_DB.RAW.STORM_STAGEDBT_DB.RAW.STORM_STAGEDBT_DB.RAW.STORM_STAGE
