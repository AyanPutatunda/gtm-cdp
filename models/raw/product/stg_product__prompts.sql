-- RAW layer: one row per prompt. Note: no metadata at all, so origin is unknowable.
select
    nullif(trim(id), '')            as prompt_id,
    nullif(trim(project_id), '')    as project_id,
    nullif(trim(user_id), '')       as user_id,
    cast(created as timestamp)        as created_at
from {{ ref('raw_prompts') }}
