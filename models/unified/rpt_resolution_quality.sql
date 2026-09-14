/*
  UNIFIED · Resolution quality scorecard
  Grain: one row per metric. The numbers behind MEMO Q2, recomputed on
  every run so drift is visible (a sudden drop in resolved % or a jump in
  conflicts is the first sign an upstream feed changed).
*/
with users as (select * from {{ ref('int_user_identity') }}),
     people as (select * from {{ ref('int_member_account_resolution') }}),
     orgs as (select * from {{ ref('int_org_account_resolution') }}),
     activity as (select * from {{ ref('int_product_activity') }}),
     companies as (select * from {{ ref('int_signal_company_resolution') }}),
     ext as (select * from {{ ref('int_external_signals') }}),
     accts as (select * from {{ ref('int_match_keys') }} where entity_type = 'account'),
     -- the one RAW read in UNIFIED, on purpose: a reconciliation metric has to
     -- compare what arrived with what could be attributed
     pages as (select * from {{ ref('stg_product__segment_pages') }}),

metrics as (
    select 1 as metric_order, 'identity' as area, 'Logins merged into an existing person (exact email)' as metric,
           sum(case when is_secondary_login then 1 else 0 end) as numerator, count(*) as denominator
    from users
    union all
    select 2, 'identity', 'Product orgs mapped to a Salesforce account',
           sum(case when account_id is not null then 1 else 0 end), count(*) from orgs
    union all
    select 3, 'identity', 'Mapped orgs whose link is low confidence (fallback)',
           sum(case when resolution_status = 'resolved_low_confidence' then 1 else 0 end),
           sum(case when account_id is not null then 1 else 0 end) from orgs
    union all
    select 4, 'identity', 'People resolved to exactly one account',
           sum(case when resolution_status = 'resolved' then 1 else 0 end), count(*) from people
    union all
    select 5, 'identity', 'People flagged ambiguous (belong to 2+ accounts)',
           sum(case when is_ambiguous then 1 else 0 end), count(*) from people
    union all
    select 6, 'activity', 'Product activities attributed to an account',
           sum(case when account_id is not null then 1 else 0 end), count(*) from activity
    union all
    select 7, 'activity', 'Page views that are anonymous (cannot be attributed)',
           sum(case when user_id is null then 1 else 0 end), count(*) from pages
    union all
    select 8, 'activity', 'Objects whose creating surface is unknown',
           sum(case when surface = 'unknown' then 1 else 0 end),
           sum(case when activity_type in ('experiment', 'dataset', 'prompt') then 1 else 0 end) from activity
    union all
    select 9, 'activity', 'Objects created by automation (CI / production jobs)',
           sum(case when actor_type = 'automation' then 1 else 0 end),
           sum(case when activity_type in ('experiment', 'dataset', 'prompt') then 1 else 0 end) from activity
    union all
    select 10, 'external', 'External companies resolved to an account',
           sum(case when resolution_status = 'resolved' then 1 else 0 end), count(*) from companies
    union all
    select 11, 'external', 'Resolved companies confirmed by 2+ independent keys (distinct values)',
           sum(case when resolution_status = 'resolved' and unique_keys_agreeing >= 2 then 1 else 0 end),
           sum(case when resolution_status = 'resolved' then 1 else 0 end) from companies
    union all
    select 12, 'external', 'Resolved companies whose name also agrees (audit proxy)',
           sum(case when name_agrees_with_match then 1 else 0 end),
           sum(case when resolution_status = 'resolved' then 1 else 0 end) from companies
    union all
    select 19, 'external', 'Resolved companies whose name points at a different account (held for review)',
           sum(case when needs_review then 1 else 0 end),
           sum(case when resolution_status = 'resolved' then 1 else 0 end) from companies
    union all
    select 13, 'external', 'External companies in conflict (keys disagree)',
           sum(case when resolution_status = 'conflict' then 1 else 0 end), count(*) from companies
    union all
    select 14, 'external', 'External companies left unresolved (any reason)',
           sum(case when resolution_status <> 'resolved' then 1 else 0 end), count(*) from companies
    union all
    select 15, 'external', 'External signals attached to an account',
           sum(case when account_id is not null then 1 else 0 end), count(*) from ext
    union all
    select 16, 'external', 'News headlines that name a different company (entity mismatch)',
           sum(case when is_entity_mismatch then 1 else 0 end),
           sum(case when signal_family = 'news' then 1 else 0 end) from ext
    union all
    select 17, 'crm', 'Salesforce accounts with no domain and no LinkedIn',
           sum(case when has_no_match_keys then 1 else 0 end), count(*) from accts
    union all
    select 18, 'crm', 'Salesforce accounts sharing a domain with another account',
           sum(case when is_domain_shared then 1 else 0 end), count(*) from accts
)

select
    metric_order,
    area,
    metric,
    numerator,
    denominator,
    case when denominator > 0 then round(1.0 * numerator / denominator, 4) end as rate
from metrics
