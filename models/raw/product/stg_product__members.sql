-- RAW layer: user <-> org membership (many-to-many).
select
    nullif(trim(org_id), '')            as org_id,
    nullif(trim(user_id), '')           as user_id,
    cast(member_created_at as timestamp)  as member_created_at
from {{ ref('raw_members') }}
