/*
  UNIFIED · Member activity by surface
  Grain: one row per person x surface (ui, sdk, cli, mcp, unknown).

  Every person gets all five rows, so "no evidence" is an explicit answer,
  not a missing row.

  TWO status columns, because they answer different questions:
    evidence_status        did this SURFACE get used under this person's
                           identity, by anyone or anything?
    human_evidence_status  did this PERSON use it? Automation running under
                           their key is excluded — that is the account using
                           the surface, not the member. dim_members pivots
                           this one, because dim_members is a view of people.
  For Bob (12 nightly CI runs) the two read usage_proven and no_evidence.

  The ladder, in both cases:
    usage_proven   a deterministic usage signal exists
    usage_likely   only heuristic usage signals exist
    intent_only    they looked into it (docs, wizard, key name) - not usage
    origin_unknown objects exist but we cannot tell which surface made them
    no_evidence    nothing
  CLI and MCP can never be better than intent_only with today's data.
*/
with surfaces as (
    select 'ui' as surface, 1 as surface_order, 'Observable: logged-in page views (raw_segment_pages.user_id)' as what_we_can_see
    union all select 'sdk', 2, 'Observable: repo_info / CI tags on objects, trace ingestion at org level. Cannot be split from CLI'
    union all select 'cli', 3, 'Not observable: only setup-wizard views and API key names (intent)'
    union all select 'mcp', 4, 'Not observable: only docs install/copy clicks (intent)'
    union all select 'unknown', 5, 'Objects with no origin metadata: UI, or SDK outside a git repo'
),

people as (
    select * from {{ ref('int_member_account_resolution') }}
),

activity as (
    select * from {{ ref('int_product_activity') }}
),

per_person_surface as (
    select
        person_id,
        surface,
        count(*)                                                                             as signal_events,
        sum(case when evidence_kind = 'usage' then 1 else 0 end)                             as usage_events,
        sum(case when evidence_kind = 'intent' then 1 else 0 end)                            as intent_events,
        sum(case when evidence_kind = 'usage' and actor_type = 'human' then 1 else 0 end)    as human_usage_events,
        sum(case when actor_type <> 'automation' then 1 else 0 end)                          as non_automated_events,
        sum(case when evidence_kind = 'usage' and actor_type = 'automation' then 1 else 0 end) as automated_usage_events,
        sum(case when is_in_lookback then 1 else 0 end)                                      as events_in_lookback,
        min(activity_at)                                                                     as first_seen_at,
        max(activity_at)                                                                     as last_seen_at,
        max(confidence_score)                                                                as max_confidence,
        max(case when evidence_kind = 'usage' and attribution = 'deterministic' then 1 else 0 end) = 1          as has_deterministic_usage,
        max(case when evidence_kind = 'usage' and attribution = 'heuristic' then 1 else 0 end) = 1              as has_heuristic_usage,
        max(case when evidence_kind = 'usage' and attribution = 'deterministic' and actor_type <> 'automation' then 1 else 0 end) = 1 as has_human_deterministic_usage,
        max(case when evidence_kind = 'usage' and attribution = 'heuristic' and actor_type <> 'automation' then 1 else 0 end) = 1     as has_human_heuristic_usage,
        max(case when evidence_kind = 'intent' then 1 else 0 end) = 1                                           as has_intent,
        {{ agg_list('signal_code') }}                                                        as signal_codes
    from activity
    group by person_id, surface
)

select
    p.person_id,
    p.email,
    p.account_id,
    p.resolution_status                                   as account_resolution_status,
    s.surface,
    s.surface_order,
    coalesce(a.signal_events, 0)                          as signal_events,
    coalesce(a.usage_events, 0)                           as usage_events,
    coalesce(a.intent_events, 0)                          as intent_events,
    coalesce(a.human_usage_events, 0)                     as human_usage_events,
    coalesce(a.automated_usage_events, 0)                 as automated_usage_events,
    coalesce(a.events_in_lookback, 0)                     as events_in_lookback,
    a.first_seen_at,
    a.last_seen_at,
    coalesce(a.max_confidence, 0)                         as max_confidence,
    case
        when s.surface = 'unknown' and coalesce(a.signal_events, 0) > 0 then 'origin_unknown'
        when a.has_deterministic_usage                                 then 'usage_proven'
        when a.has_heuristic_usage                                     then 'usage_likely'
        when a.has_intent                                              then 'intent_only'
        else 'no_evidence'
    end                                                   as evidence_status,
    -- the same ladder, but automation running under this person's key does
    -- not make the PERSON a user of the surface
    case
        when s.surface = 'unknown' and coalesce(a.non_automated_events, 0) > 0 then 'origin_unknown'
        when a.has_human_deterministic_usage                                   then 'usage_proven'
        when a.has_human_heuristic_usage                                       then 'usage_likely'
        when a.has_intent                                                      then 'intent_only'
        else 'no_evidence'
    end                                                   as human_evidence_status,
    case
        when coalesce(a.usage_events, 0) = 0                                   then null
        when a.human_usage_events > 0 and a.automated_usage_events > 0         then 'human_and_automation'
        when a.automated_usage_events > 0                                      then 'automation_only'
        when a.human_usage_events > 0                                          then 'human'
        else 'unknown'
    end                                                   as usage_actor,
    a.signal_codes,
    s.what_we_can_see
from people as p
cross join surfaces as s
left join per_person_surface as a
    on p.person_id = a.person_id
   and s.surface   = a.surface
