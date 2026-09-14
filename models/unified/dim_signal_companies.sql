/*
  UNIFIED · External companies and how they resolved
  Grain: one row per external company. Unresolved companies are kept:
  a CDP never silently drops a record. next_action tells a human (or a
  workflow) what to do with each one.
*/
with resolution as (
    select * from {{ ref('int_signal_company_resolution') }}
),

signals as (
    select
        company_id,
        count(*)                                                   as signals_total,
        sum(case when is_in_lookback then 1 else 0 end)            as signals_in_lookback,
        sum(case when is_entity_mismatch then 1 else 0 end)        as signals_entity_mismatch,
        max(occurred_at)                                           as latest_signal_at
    from {{ ref('int_external_signals') }}
    group by company_id
),

accounts as (
    select entity_id as account_id, entity_name as account_name
    from {{ ref('int_match_keys') }}
    where entity_type = 'account'
)

select
    r.company_id,
    r.company_name,
    r.website_domain,
    r.linkedin_slug,
    r.linkedin_domain,
    r.resolution_status,
    r.account_id,
    a.account_name,
    r.match_method,
    r.match_confidence,
    r.is_conflict,
    r.keys_matched,
    r.keys_agreeing,
    r.match_evidence,
    r.candidate_account_ids,
    r.name_match_account_id,
    n.account_name                           as name_match_account_name,
    r.name_agrees_with_match,
    r.needs_review,
    r.is_website_shared_in_feed,
    r.next_action,
    coalesce(s.signals_total, 0)             as signals_total,
    coalesce(s.signals_in_lookback, 0)       as signals_in_lookback,
    coalesce(s.signals_entity_mismatch, 0)   as signals_entity_mismatch,
    s.latest_signal_at
from resolution as r
left join signals  as s on r.company_id = s.company_id
left join accounts as a on r.account_id = a.account_id
left join accounts as n on r.name_match_account_id = n.account_id
