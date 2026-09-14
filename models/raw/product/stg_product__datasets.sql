-- RAW layer: one row per dataset.
with source as (
    select
        nullif(trim(id), '')            as dataset_id,
        nullif(trim(project_id), '')    as project_id,
        nullif(trim(user_id), '')       as user_id,
        cast(created as timestamp)        as created_at,
        nullif(trim(metadata), '')      as metadata_json
    from {{ ref('raw_datasets') }}
)

select
    dataset_id,
    project_id,
    user_id,
    created_at,
    metadata_json,
    {{ json_get('metadata_json', 'source') }}  as meta_source
from source
