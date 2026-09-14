/*
  UNIFIED · Net-new prospects
  Grain: one row per prospect. Two doors in:
    external_signal  - an external company with identifiers that match no
                       Salesforce account (sc10 Prospect AI)
    product_signup   - a product org mapped to no Salesforce account
                       (org_nomap 'Startup Sandbox')
  Unresolved records are an OUTPUT of the CDP, not an error to hide.
*/
with external as (
    select
        'external:' || c.company_id                          as prospect_id,
        'external_signal'                                    as prospect_source,
        c.company_name                                       as prospect_name,
        c.website_domain                                     as domain,
        c.linkedin_slug,
        cast(null as varchar)                                as product_plan,
        0                                                    as product_members,
        c.signals_in_lookback,
        c.latest_signal_at                                   as last_seen_at,
        'External activity from a company with no CRM account'  as why_it_matters
    from {{ ref('dim_signal_companies') }} as c
    where c.next_action = 'net_new_prospect'
),

latest_headline as (
    select company_id, headline
    from {{ ref('int_external_signals') }}
    where signal_family = 'news'
    qualify row_number() over (partition by company_id order by occurred_at desc, signal_id) = 1
),

signups as (
    select
        o.org_id,
        o.org_name,
        o.plan,
        count(distinct m.person_id)                          as product_members,
        max(p.email_domain)                                  as email_domain
    from {{ ref('int_org_account_resolution') }} as o
    left join {{ ref('int_memberships') }}               as m on o.org_id = m.org_id
    left join {{ ref('int_member_account_resolution') }} as p on m.person_id = p.person_id
    where o.resolution_status = 'unmapped'
    group by o.org_id, o.org_name, o.plan
),

signup_activity as (
    select org_id, sum(case when is_in_lookback then 1 else 0 end) as events_in_lookback, max(activity_at) as last_seen_at
    from {{ ref('int_product_activity') }}
    group by org_id
),

product as (
    select
        'product:' || s.org_id                               as prospect_id,
        'product_signup'                                     as prospect_source,
        s.org_name                                           as prospect_name,
        s.email_domain                                       as domain,
        cast(null as varchar)                                as linkedin_slug,
        s.plan                                               as product_plan,
        s.product_members,
        coalesce(a.events_in_lookback, 0)                    as signals_in_lookback,
        a.last_seen_at,
        'Product sign-up using us today with no CRM account' as why_it_matters
    from signups as s
    left join signup_activity as a on s.org_id = a.org_id
)

select
    e.*,
    h.headline                                               as latest_headline
from external as e
left join latest_headline as h
    on e.prospect_id = 'external:' || h.company_id

union all

select
    p.*,
    cast(null as varchar)                                    as latest_headline
from product as p
