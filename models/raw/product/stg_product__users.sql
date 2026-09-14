-- RAW layer: one row per product login (user_id). Typed, nothing interpreted.
select
    nullif(trim(user_id), '')           as user_id,
    nullif(trim(email), '')             as email,
    cast(created_at as timestamp)         as created_at
from {{ ref('raw_users') }}
