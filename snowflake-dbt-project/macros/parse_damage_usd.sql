{% macro parse_damage_usd(damage_col) -%}
-- Convert NOAA damage tokens (e.g. '1.00K', '0.50M', '1.00B', '0', '0.00K', NULL)
-- into a numeric USD amount. K = thousand, M = million, B = billion.
-- NULL / '0' / '0.00' / '0.00K' / '0K' all = 0.
CASE
    WHEN {{ damage_col }} IS NULL THEN 0
    WHEN upper({{ damage_col }}) LIKE '%.%K' OR upper({{ damage_col }}) LIKE '%K'
        THEN TRY_TO_NUMBER(REPLACE(upper({{ damage_col }}), 'K', '')) * 1000
    WHEN upper({{ damage_col }}) LIKE '%.%M' OR upper({{ damage_col }}) LIKE '%M'
        THEN TRY_TO_NUMBER(REPLACE(upper({{ damage_col }}), 'M', '')) * 1000000
    WHEN upper({{ damage_col }}) LIKE '%.%B' OR upper({{ damage_col }}) LIKE '%B'
        THEN TRY_TO_NUMBER(REPLACE(upper({{ damage_col }}), 'B', '')) * 1000000000
    ELSE COALESCE(TRY_TO_NUMBER({{ damage_col }}), 0)
END
{%- endmacro %}
