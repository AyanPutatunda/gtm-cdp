-- RAW layer: one row per product org (workspace).
select
    nullif(trim(org_id), '')            as org_id,
    nullif(trim(org_name), '')          as org_name,
    cast(created_at as timestamp)         as created_at,
    nullif(trim(plan), '')              as plan
from {{ ref('raw_organizations') }}
