-- RAW layer: one row per experiment. repo_info / metadata are JSON-as-text:
-- parsed here into plain columns so later layers never touch JSON.
with source as (
    select
        nullif(trim(id), '')            as experiment_id,
        nullif(trim(project_id), '')    as project_id,
        nullif(trim(user_id), '')       as user_id,
        cast(created as timestamp)        as created_at,
        nullif(trim(repo_info), '')     as repo_info_json,
        nullif(trim(metadata), '')      as metadata_json
    from {{ ref('raw_experiments') }}
)

select
    experiment_id,
    project_id,
    user_id,
    created_at,
    repo_info_json,
    metadata_json,
    repo_info_json is not null                                        as has_repo_info,
    {{ json_get('repo_info_json', 'commit') }}                        as repo_commit,
    {{ json_get('repo_info_json', 'branch') }}                        as repo_branch,
    try_cast({{ json_get('repo_info_json', 'dirty') }} as boolean)    as repo_is_dirty,
    {{ json_get('repo_info_json', 'author_name') }}                   as repo_author_name,
    try_cast({{ json_get('repo_info_json', 'commit_time') }} as timestamp) as repo_commit_time,
    {{ json_get('metadata_json', 'eval_name') }}                      as meta_eval_name,
    {{ json_get('metadata_json', 'model') }}                          as meta_model,
    {{ json_get('metadata_json', 'source') }}                         as meta_source,
    {{ json_get('metadata_json', 'ci_run_id') }}                      as meta_ci_run_id,
    {{ json_get('metadata_json', 'ci') }}                             as meta_ci_flag
from source
