/*
  UNIFIED · Members
  Grain: one row per person (a deduplicated human behind one or more logins).

  One place to answer "who is this, which account are they in, and how do
  they use us?". Surface columns are pivoted from fct_member_surface_activity.

  The *_evidence columns pivot human_evidence_status, not evidence_status:
  this is a view of PEOPLE, so a nightly CI job running under someone's key
  does not make that person an SDK user. The machine side is still visible,
  never hidden — sdk_evidence_any_actor, sdk_usage_actor,
  automated_usage_events and member_type all report it.

  member_type
    automation_identity  every usage event we can attribute came from automation
                         (Bob: 12 nightly CI experiments + a CI dataset, nothing human).
                         The login is real; the activity is a machine using its key.
    human                at least one event shows a person at the keyboard
    undetermined         activity exists but only as objects of unknown origin (Grace):
                         active, but we don't guess whether a person or a script did it
*/
with people as (
    select * from {{ ref('int_member_account_resolution') }}
),

surface as (
    select * from {{ ref('fct_member_surface_activity') }}
),

pivoted as (
    select
        person_id,
        max(case when surface = 'ui'  then human_evidence_status end) as ui_evidence,
        max(case when surface = 'sdk' then human_evidence_status end) as sdk_evidence,
        max(case when surface = 'cli' then human_evidence_status end) as cli_evidence,
        max(case when surface = 'mcp' then human_evidence_status end) as mcp_evidence,
        max(case when surface = 'sdk' then evidence_status end)       as sdk_evidence_any_actor,
        max(case when surface = 'sdk' then usage_actor end)           as sdk_usage_actor,
        sum(case when surface = 'ui'  then usage_events else 0 end)   as ui_page_views,
        sum(case when surface = 'sdk' then usage_events else 0 end)   as sdk_objects,
        sum(case when surface = 'unknown' then usage_events else 0 end) as objects_origin_unknown,
        sum(case when surface in ('cli', 'mcp') then intent_events else 0 end) as cli_mcp_intent_events,
        sum(human_usage_events)                                       as human_usage_events,
        sum(automated_usage_events)                                   as automated_usage_events,
        sum(events_in_lookback)                                       as events_in_lookback,
        max(last_seen_at)                                             as last_seen_at
    from surface
    group by person_id
),

keys as (
    select
        person_id,
        count(*)                                      as api_key_count,
        {{ agg_list('key_name') }}                    as api_key_names,
        max(case when is_automation_named then 1 else 0 end) = 1         as has_automation_named_key
    from {{ ref('int_api_keys') }}
    group by person_id
)

select
    p.person_id,
    p.email,
    p.email_domain,
    p.login_count,
    p.user_ids,
    p.login_count > 1                                  as has_duplicate_logins,
    p.org_ids,
    p.account_id,
    p.account_confidence,
    p.resolution_status                                as account_resolution_status,
    p.candidate_account_ids,
    case
        when v.automated_usage_events > 0 and v.human_usage_events = 0 and v.objects_origin_unknown = 0
            then 'automation_identity'
        when v.human_usage_events > 0
            then 'human'
        else 'undetermined'
    end                                                as member_type,
    v.ui_evidence,
    v.sdk_evidence,
    v.cli_evidence,
    v.mcp_evidence,
    v.sdk_evidence_any_actor,
    v.sdk_usage_actor,
    v.ui_page_views,
    v.sdk_objects,
    v.objects_origin_unknown,
    v.cli_mcp_intent_events,
    v.human_usage_events,
    v.automated_usage_events,
    v.events_in_lookback,
    v.last_seen_at,
    coalesce(k.api_key_count, 0)                       as api_key_count,
    k.api_key_names,
    coalesce(k.has_automation_named_key, false)        as has_automation_named_key
from people as p
left join pivoted as v on p.person_id = v.person_id
left join keys    as k on p.person_id = k.person_id
