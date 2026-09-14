/*
  UNIFIED · The account signal feed
  Grain: one row per signal attached to a Salesforce account.

  This is the extension point of the platform. Product and external signals
  share one shape:
      account_id | signal_source | signal_type | occurred_at | headline
      | signal_confidence | attribution | attribution_confidence
      | is_actionable | needs_review
  Adding a new source (intent data, support tickets, billing) = one more
  union branch here. account_360 takes its reasons, headlines and review
  counts from this feed, as would any alerting or reverse-ETL.

  is_actionable (v0 rules, all visible below):
    - every signal: the link that put it on the account is at least
      min_attribution_confidence, and nothing about it needs review
    - external news/product: inside the lookback window, vendor confidence
      >= min_vendor_confidence (that threshold gates the VENDOR's own
      confidence and nothing else; product-side signals carry their
      confidence from ref_surface_signals and are gated on attribution)
    - usage surge: 7-day trace growth >= usage_surge_threshold
    - CLI/MCP intent: members exploring a surface we can help them adopt
    - tech detections and CI automation are context, not a reason to call
*/
with external as (
    select
        account_id,
        'external'                                         as signal_source,
        signal_type,
        signal_id,
        occurred_at,
        headline,
        coalesce(vendor_confidence, 0.80)                  as signal_confidence,
        'external_id_' || match_method                     as attribution,
        match_confidence                                   as attribution_confidence,
        is_in_lookback
            and signal_family in ('news', 'product')
            and coalesce(vendor_confidence, 0.80) >= {{ var('min_vendor_confidence') }}
            and match_confidence >= {{ var('min_attribution_confidence') }}
            and not is_entity_mismatch
            and not is_match_pending_review                as is_actionable,
        is_entity_mismatch or is_match_pending_review      as needs_review,
        company_id                                         as source_entity_id
    from {{ ref('int_external_signals') }}
    where resolution_status = 'resolved'
),

-- the org-level trace rule, read from the rules seed rather than hardcoded here
trace_rule as (
    select surface, confidence_score
    from {{ ref('ref_surface_signals') }}
    where signal_code = 'org_trace_ingestion'
),

org_plans as (
    select
        account_id,
        max(plan_rank)              as best_plan_rank,
        min(mapping_confidence)     as weakest_org_link     -- product signals inherit the weakest org->account link
    from {{ ref('int_org_account_resolution') }}
    where account_id is not null
    group by account_id
),

usage_surge as (
    -- growth is NOT recomputed here: int_account_trace_trend owns that number
    select
        u.account_id,
        'product'                                          as signal_source,
        'usage_surge'                                      as signal_type,
        'usage_surge:' || u.account_id                     as signal_id,
        cast(u.last_day as timestamp)                      as occurred_at,
        'Trace ingestion up ' || cast(cast(round(100 * u.trace_growth_7d, 0) as integer) as varchar)
            || '% in 7 days (' || cast(round(u.gb_baseline_day, 1) as varchar) || ' -> ' || cast(round(u.gb_last_day, 1) as varchar) || ' GB/day)'
            || case when p.best_plan_rank < 3 then ' on a non-Enterprise plan' else '' end
                                                           as headline,
        tr.confidence_score                                as signal_confidence,
        'org_trace_ingestion'                              as attribution,
        p.weakest_org_link                                 as attribution_confidence,
        p.weakest_org_link >= {{ var('min_attribution_confidence') }} as is_actionable,
        p.weakest_org_link <  {{ var('min_attribution_confidence') }} as needs_review,
        u.account_id                                       as source_entity_id
    from {{ ref('int_account_trace_trend') }} as u
    cross join trace_rule as tr
    left join org_plans as p on u.account_id = p.account_id
    where u.is_usage_surge
),

product_activity as (
    select * from {{ ref('int_product_activity') }}
    where account_id is not null and is_in_lookback
),

automation as (
    select
        account_id,
        'product'                                          as signal_source,
        'ci_automation'                                    as signal_type,
        'ci_automation:' || account_id                     as signal_id,
        max(activity_at)                                   as occurred_at,
        cast(count(*) as varchar) || ' objects created by automation (CI / production jobs) in the last {{ var("lookback_days") }} days' as headline,
        0.90                                               as signal_confidence,
        'org_account'                                      as attribution,
        min(account_confidence)                            as attribution_confidence,
        false                                              as is_actionable,
        false                                              as needs_review,
        account_id                                         as source_entity_id
    from product_activity
    where actor_type = 'automation' and surface = 'sdk'
    group by account_id
),

surface_intent as (
    select
        account_id,
        'product'                                          as signal_source,
        'surface_intent'                                   as signal_type,
        'surface_intent:' || account_id                    as signal_id,
        max(activity_at)                                   as occurred_at,
        cast(count(distinct person_id) as varchar) || ' member(s) exploring '
            || upper({{ agg_list('surface') }}) || ' setup (intent, not proven usage)'
                                                           as headline,
        0.30                                               as signal_confidence,
        max(account_attribution)                           as attribution,
        min(account_confidence)                            as attribution_confidence,
        min(account_confidence) >= {{ var('min_attribution_confidence') }} as is_actionable,
        min(account_confidence) <  {{ var('min_attribution_confidence') }} as needs_review,
        account_id                                         as source_entity_id
    from product_activity
    where evidence_kind = 'intent' and surface in ('cli', 'mcp')
    group by account_id
),

unioned as (
    select * from external
    union all select * from usage_surge
    union all select * from automation
    union all select * from surface_intent
)

select
    u.signal_id,
    u.account_id,
    a.account_name,
    u.signal_source,
    u.signal_type,
    u.occurred_at,
    u.headline,
    cast(u.signal_confidence as double)          as signal_confidence,
    u.attribution,
    u.attribution_confidence,
    u.is_actionable,
    u.needs_review,
    u.source_entity_id
from unioned as u
inner join (
    select entity_id as account_id, entity_name as account_name
    from {{ ref('int_match_keys') }}
    where entity_type = 'account'
) as a on u.account_id = a.account_id
