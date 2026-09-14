/*
  CLEANSED · Product activity, classified by surface
  Grain: one row per product activity (object created, page viewed,
  wizard opened, docs click, API key).

  Every row answers four questions honestly:
    1. WHICH surface?        ui / sdk / cli / mcp / unknown
    2. WHAT kind of proof?   usage (it happened) vs intent (they looked into it)
    3. HOW sure?             deterministic / heuristic / none + a 0-1 score
    4. WHO acted?            human / automation / unknown

  What each signal means (surface, usage vs intent, confidence, what it can
  and cannot prove) lives in the seed ref_surface_signals. The CASE
  expressions below only DETECT which signal a row is.

  About user_id on objects: it is the login whose session or API key made the
  call, not necessarily the human who acted. Bob's 12 nightly experiments
  (02:01-02:12) are a GitHub Actions job using his "ci-service" key. So we classify the ACTOR
  separately from the login and never count automation as human engagement.
*/

-- ---------------------------------------------------------------- objects ----
with experiments as (
    select
        'experiment:' || experiment_id                         as activity_id,
        'raw_experiments'                                       as source_table,
        'experiment'                                            as activity_type,
        experiment_id                                           as object_id,
        user_id,
        project_id,
        cast(null as varchar)                                   as direct_org_id,
        created_at                                              as activity_at,
        case
            when meta_ci_run_id is not null
              or lower(meta_ci_flag) in ('true', '1', 'yes')
              or lower(meta_source) like 'ci%'
              or lower(repo_author_name) like '%ci-runner%'
              or lower(repo_author_name) like '%[bot]%'           then 'code_ci_run'
            when has_repo_info                                  then 'code_repo_info'
            when meta_source is not null                        then 'code_runtime_source'
            else 'object_origin_unknown'
        end                                                     as signal_code,
        case
            when meta_ci_run_id is not null
              or lower(meta_ci_flag) in ('true', '1', 'yes')
              or lower(meta_source) like 'ci%'
              or lower(repo_author_name) like '%ci-runner%'
              or lower(repo_author_name) like '%[bot]%'           then 'automation'
            when repo_is_dirty                                  then 'human'
            when meta_source is not null and not has_repo_info  then 'automation'
            when has_repo_info                                  then 'human'
            else 'unknown'
        end                                                     as actor_type,
        case
            when meta_ci_run_id is not null                     then 'metadata.ci_run_id present'
            when lower(meta_ci_flag) in ('true', '1', 'yes')    then 'metadata.ci = true'
            when lower(meta_source) like 'ci%'                  then 'metadata.source = ' || meta_source
            when lower(repo_author_name) like '%ci-runner%'
              or lower(repo_author_name) like '%[bot]%'          then 'repo_info.author_name = ' || repo_author_name
            when repo_is_dirty                                  then 'repo_info.dirty = true (uncommitted local run)'
            when meta_source is not null and not has_repo_info  then 'metadata.source = ' || meta_source || ' (server-side process)'
            when has_repo_info                                  then 'repo_info present, committed code'
            else 'no repo_info, no metadata tags'
        end                                                     as evidence_detail
    from {{ ref('stg_product__experiments') }}
),

datasets as (
    select
        'dataset:' || dataset_id,
        'raw_datasets',
        'dataset',
        dataset_id,
        user_id,
        project_id,
        cast(null as varchar),
        created_at,
        case when lower(meta_source) like 'ci%' then 'code_ci_run'
             else 'object_origin_unknown' end,
        case when lower(meta_source) like 'ci%'  then 'automation'
             when lower(meta_source) = 'manual'  then 'human'
             else 'unknown' end,
        case when meta_source is not null then 'metadata.source = ' || meta_source
             else 'no metadata' end
    from {{ ref('stg_product__datasets') }}
),

prompts as (
    select
        'prompt:' || prompt_id,
        'raw_prompts',
        'prompt',
        prompt_id,
        user_id,
        project_id,
        cast(null as varchar),
        created_at,
        'object_origin_unknown',
        'unknown',
        'prompts carry no origin metadata'
    from {{ ref('stg_product__prompts') }}
),

-- ------------------------------------------------- browser & account events --
page_views as (
    select
        'page_view:' || coalesce(anonymous_id, '') || ':' || user_id || ':' || cast(viewed_at as varchar) || ':' || page_path,
        'raw_segment_pages',
        'page_view',
        page_path,
        user_id,
        cast(null as varchar),
        cast(null as varchar),
        viewed_at,
        'ui_page_view',
        'human',
        'logged-in page view: ' || page_path
    from {{ ref('stg_product__segment_pages') }}
    where user_id is not null          -- anonymous traffic can't be attributed; counted in rpt_resolution_quality
),

cli_wizard as (
    select
        'cli_wizard:' || user_id || ':' || cast(event_at as varchar),
        'raw_cli_wizard',
        'cli_setup_wizard',
        cast(null as varchar),
        user_id,
        cast(null as varchar),
        cast(null as varchar),
        event_at,
        'cli_setup_wizard',
        'human',
        'opened CLI setup wizard (browser)'
    from {{ ref('stg_product__cli_wizard') }}
),

docs_mcp as (
    select
        'docs_mcp:' || user_id || ':' || cast(event_at as varchar) || ':' || action,
        'raw_docs_mcp_events',
        'docs_mcp_click',
        action,
        user_id,
        cast(null as varchar),
        cast(null as varchar),
        event_at,
        'mcp_docs_click',
        'human',
        'docs click: ' || action
    from {{ ref('stg_product__docs_mcp_events') }}
),

cli_key_hints as (
    select
        'api_key:' || api_key_id,
        'raw_api_keys',
        'api_key',
        api_key_id,
        user_id,
        cast(null as varchar),
        org_id,                             -- a key belongs to an org: attribute through it
        cast(null as timestamp),            -- keys carry no created timestamp
        'cli_key_name_hint',
        'unknown',
        'API key named "' || key_name || '"'
    from {{ ref('int_api_keys') }}
    where is_cli_named
),

unioned as (
    select * from experiments
    union all select * from datasets
    union all select * from prompts
    union all select * from page_views
    union all select * from cli_wizard
    union all select * from docs_mcp
    union all select * from cli_key_hints
),

-- remove exact duplicates (same event delivered twice)
deduped as (
    select *
    from unioned
    qualify row_number() over (partition by activity_id order by activity_at) = 1
),

projects as (
    select project_id, org_id from {{ ref('stg_product__projects') }}
),

located as (
    -- objects take the org of their project; keys carry their own org; browser events have none
    select d.*, coalesce(p.org_id, d.direct_org_id) as org_id
    from deduped as d
    left join projects as p on d.project_id = p.project_id
),

orgs as (
    select org_id, account_id, resolution_status, mapping_confidence from {{ ref('int_org_account_resolution') }}
),

people as (
    select person_id, account_id, resolution_status, account_confidence from {{ ref('int_member_account_resolution') }}
)

select
    d.activity_id,
    d.source_table,
    d.activity_type,
    d.object_id,
    d.user_id,
    i.person_id,
    d.project_id,
    d.org_id,
    d.activity_at,
    d.activity_at is not null
        and cast(d.activity_at as date) >  {{ lookback_start() }}
        and cast(d.activity_at as date) <= {{ as_of_date() }}          as is_in_lookback,

    -- surface classification (from ref_surface_signals)
    d.signal_code,
    s.surface,
    s.evidence_kind,
    s.attribution,
    cast(s.confidence_score as double)                                 as confidence_score,
    d.actor_type,
    d.evidence_detail,

    -- account attribution
    -- objects: project -> org -> account (deterministic, independent of who the user is)
    -- api keys: the key's own org -> account
    -- browser events: only when the person belongs to exactly one account
    case
        when d.org_id is not null and o.resolution_status in ('resolved', 'resolved_low_confidence') then o.account_id
        when d.org_id is null and pe.resolution_status = 'resolved'                                   then pe.account_id
    end                                                                as account_id,
    case
        when d.org_id is not null and o.resolution_status in ('resolved', 'resolved_low_confidence') then 'org_account'
        when d.org_id is not null                                      then 'org_' || o.resolution_status
        when pe.resolution_status = 'resolved'                         then 'single_account_member'
        else 'person_' || coalesce(pe.resolution_status, 'unknown')
    end                                                                as account_attribution,
    case when o.resolution_status in ('resolved', 'resolved_low_confidence') then o.mapping_confidence
         when d.org_id is null and pe.resolution_status = 'resolved' then pe.account_confidence
    end                                                                as account_confidence
from located as d
left join {{ ref('int_user_identity') }} as i  on d.user_id    = i.user_id
left join orgs                            as o  on d.org_id     = o.org_id
left join people                          as pe on i.person_id  = pe.person_id
left join {{ ref('ref_surface_signals') }} as s on d.signal_code = s.signal_code
