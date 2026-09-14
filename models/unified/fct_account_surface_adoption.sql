/*
  UNIFIED · Account surface adoption
  Grain: one row per Salesforce account x surface (ui, sdk, cli, mcp).

  Denominator = known product members of the account: people with a
  membership in any org mapped to it. That is NOT the account's headcount,
  and the columns say so.

  Numerators only count activity that was ATTRIBUTED to this account
  (project -> org -> account, or a person who belongs to only this account).
  A multi-account person's browser events are counted separately as
  unattributed, never guessed onto one account.

  Members only count as users when a person (or an unknown actor) did it.
  Runs by automation under a member's key prove the ACCOUNT uses the
  surface, but are reported separately and never make a member "active".

  For CLI and MCP, pct_members_usage_proven is null on purpose: usage is not
  measurable from this data. Only intent is reported.

  evidence_level says at WHICH GRAIN the evidence sits, so a dashboard can
  never render "usage_proven" next to "0% of members" without the caveat:
    member  at least one identified member's own activity supports the status
    org     the only proof is org-level (trace ingestion, or automation
            running under a member's key) — no member is shown as a user
    none    nothing

  Time window: everything in the snapshot (adoption is a state, not a trend).
*/
-- The surface list and whether usage is measurable are DERIVED from the rules
-- seed, not asserted here: a surface is measurable only if some signal in
-- ref_surface_signals proves usage rather than intent. CLI and MCP fall out as
-- not-measurable on their own. If a real CLI usage signal is ever added to the
-- seed, this model starts reporting it without a code change.
with surfaces as (
    select
        surface,
        case surface when 'ui' then 1 when 'sdk' then 2 when 'cli' then 3 when 'mcp' then 4 else 9 end
                                                                as surface_order,
        max(case when evidence_kind = 'usage' then 1 else 0 end) = 1
                                                                as usage_is_measurable
    from {{ ref('ref_surface_signals') }}
    where surface <> 'unknown'
    group by surface
),

accounts as (
    select entity_id as account_id, entity_name as account_name
    from {{ ref('int_match_keys') }}
    where entity_type = 'account'
),

account_members as (
    select distinct account_id, person_id
    from {{ ref('int_memberships') }}
    where account_id is not null
),

member_counts as (
    select account_id, count(*) as known_members
    from account_members
    group by account_id
),

-- per account x surface x person: the strongest evidence attributed to this account
attributed as (
    select
        account_id,
        surface,
        person_id,
        -- a member only counts when a person (or an unknown actor) did it, never automation
        max(case when evidence_kind = 'usage' and attribution = 'deterministic' and actor_type <> 'automation' then 1 else 0 end) = 1 as has_proven_usage,
        max(case when evidence_kind = 'usage' and attribution = 'heuristic' and actor_type <> 'automation' then 1 else 0 end) = 1     as has_likely_usage,
        max(case when evidence_kind = 'usage' and actor_type = 'automation' then 1 else 0 end) = 1                                   as has_automated_usage,
        max(case when evidence_kind = 'intent' then 1 else 0 end) = 1                                   as has_intent,
        sum(case when evidence_kind = 'usage' then 1 else 0 end)                     as usage_events,
        sum(case when evidence_kind = 'usage' and actor_type = 'automation' then 1 else 0 end) as automated_usage_events
    from {{ ref('int_product_activity') }}
    where account_id is not null
      and surface in ('ui', 'sdk', 'cli', 'mcp')
    group by account_id, surface, person_id
),

surface_rollup as (
    select
        account_id,
        surface,
        sum(case when has_proven_usage then 1 else 0 end)                                           as members_usage_proven,
        sum(case when not has_proven_usage and has_likely_usage then 1 else 0 end)                  as members_usage_likely,
        sum(case when not has_proven_usage and not has_likely_usage and has_intent then 1 else 0 end) as members_intent_only,
        sum(case when has_automated_usage and not has_proven_usage and not has_likely_usage then 1 else 0 end) as members_automation_only,
        sum(usage_events)                                                                           as usage_events,
        sum(automated_usage_events)                                                                 as automated_usage_events
    from attributed
    group by account_id, surface
),

-- signals from members of this account that could not be attributed (multi-account people)
unattributed as (
    select
        am.account_id,
        a.surface,
        count(distinct a.person_id) as members_with_unattributed_signals
    from {{ ref('int_product_activity') }} as a
    inner join account_members as am
        on a.person_id = am.person_id
    where a.account_id is null
      and a.surface in ('ui', 'sdk', 'cli', 'mcp')
    group by am.account_id, a.surface
),

-- org-level proof of SDK usage: traces are ingested programmatically
org_level_sdk as (
    select account_id, trace_gb_last_7d
    from {{ ref('int_account_trace_trend') }}
)

select
    a.account_id,
    a.account_name,
    s.surface,
    s.surface_order,
    s.usage_is_measurable,
    coalesce(mc.known_members, 0)                                   as known_members,
    coalesce(r.members_usage_proven, 0)                             as members_usage_proven,
    coalesce(r.members_usage_likely, 0)                             as members_usage_likely,
    coalesce(r.members_intent_only, 0)                              as members_intent_only,
    coalesce(r.members_automation_only, 0)                          as members_automation_only,
    coalesce(u.members_with_unattributed_signals, 0)                as members_with_unattributed_signals,
    coalesce(r.usage_events, 0)                                     as usage_events,
    coalesce(r.automated_usage_events, 0)                           as automated_usage_events,
    case when s.surface = 'sdk' then coalesce(t.trace_gb_last_7d, 0) end as org_level_trace_gb_last_7d,
    case
        when coalesce(r.members_usage_proven, 0) > 0
          or coalesce(r.automated_usage_events, 0) > 0
          or (s.surface = 'sdk' and coalesce(t.trace_gb_last_7d, 0) > 0)   then 'usage_proven'
        when coalesce(r.members_usage_likely, 0) > 0                        then 'usage_likely'
        when coalesce(r.members_intent_only, 0) > 0                         then 'intent_only'
        when not s.usage_is_measurable                                      then 'not_measurable'
        else 'no_evidence'
    end                                                             as account_evidence_status,
    case
        when coalesce(r.members_usage_proven, 0) > 0
          or coalesce(r.members_usage_likely, 0) > 0
          or coalesce(r.members_intent_only, 0) > 0                         then 'member'
        when coalesce(r.automated_usage_events, 0) > 0
          or (s.surface = 'sdk' and coalesce(t.trace_gb_last_7d, 0) > 0)    then 'org'
        else 'none'
    end                                                             as evidence_level,
    case when s.usage_is_measurable and coalesce(mc.known_members, 0) > 0
         then round(1.0 * coalesce(r.members_usage_proven, 0) / mc.known_members, 4) end
                                                                    as pct_members_usage_proven,
    case when coalesce(mc.known_members, 0) > 0
         then round(1.0 * coalesce(r.members_intent_only, 0) / mc.known_members, 4) end
                                                                    as pct_members_intent_only,
    case
        when coalesce(mc.known_members, 0) = 0 then 'No product members mapped to this account.'
        when s.usage_is_measurable then
            cast(coalesce(r.members_usage_proven, 0) as varchar) || ' of ' || cast(mc.known_members as varchar)
            || ' known members show proven '
            || case when s.surface = 'sdk' then 'code-based (SDK, or CLI running the SDK)' else upper(s.surface) end || ' usage'
            || case when coalesce(r.automated_usage_events, 0) > 0
                    then '; ' || cast(r.automated_usage_events as varchar) || ' more runs came from automation (CI / production jobs) using a member''s key' else '' end
            || case when s.surface = 'sdk' and coalesce(t.trace_gb_last_7d, 0) > 0
                    then '; the org also ingests traces programmatically (' || cast(round(t.trace_gb_last_7d, 1) as varchar) || ' GB in 7 days, not attributable to a member)' else '' end
        else
            upper(s.surface) || ' usage is not measurable; ' || cast(coalesce(r.members_intent_only, 0) as varchar)
            || ' of ' || cast(mc.known_members as varchar) || ' known members showed setup intent'
            || case when coalesce(u.members_with_unattributed_signals, 0) > 0
                    then ' (intent from ' || cast(u.members_with_unattributed_signals as varchar)
                         || ' member(s) who also belong to another account is not counted)' else '' end
    end                                                             as honest_summary
from accounts as a
cross join surfaces as s
left join member_counts as mc on a.account_id = mc.account_id
left join surface_rollup as r on a.account_id = r.account_id and s.surface = r.surface
left join unattributed   as u on a.account_id = u.account_id and s.surface = u.surface
left join org_level_sdk  as t on a.account_id = t.account_id
