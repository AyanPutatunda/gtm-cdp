/*
  CLEANSED · Org -> Salesforce account
  Grain: one row per product org. EVERY org is kept, mapped or not.

  Decisions
  - Confidence comes from HOW the link was made (ref_org_mapping_sources):
    contract 0.95 > billing_parent 0.85 > org_c_fallback 0.50.
  - If an org points at more than one account we do not pick one: the
    account stays null and is_ambiguous = true.
  - Unmapped orgs (org_nomap) stay in with status 'unmapped' — they are
    product sign-ups with no CRM account, i.e. prospects, not errors.
  - Plan is case-normalised (Enterprise -> enterprise) and ranked.
*/
with orgs as (
    select
        org_id,
        org_name,
        lower(plan)                                   as plan,
        created_at
    from {{ ref('stg_product__organizations') }}
    qualify row_number() over (partition by org_id order by created_at) = 1
),

sources as (
    select * from {{ ref('ref_org_mapping_sources') }}
),

links as (
    select
        m.org_id,
        m.account_id,
        lower(m.mapping_source)                       as mapping_source,
        coalesce(s.confidence_score, 0.30)            as mapping_confidence,
        coalesce(s.precedence, 99)                    as precedence,
        a.account_id is not null                      as account_exists_in_crm
    from {{ ref('stg_crm__account_org_map') }} as m
    left join sources as s
        on lower(m.mapping_source) = s.mapping_source
    left join {{ ref('stg_crm__salesforce_accounts') }} as a
        on m.account_id = a.account_id
    -- the same org/account pair listed twice collapses to its best source
    qualify row_number() over (partition by m.org_id, m.account_id order by coalesce(s.precedence, 99)) = 1
),

per_org as (
    select
        org_id,
        count(distinct account_id)                    as candidate_account_count,
        {{ agg_list('account_id') }}                  as candidate_account_ids
    from links
    group by org_id
),

best_link as (
    select *
    from links
    qualify row_number() over (partition by org_id order by precedence, account_id) = 1
)

select
    o.org_id,
    o.org_name,
    o.plan,
    case o.plan when 'enterprise' then 3 when 'pro' then 2 when 'free' then 1 else 0 end as plan_rank,
    o.created_at,
    case when p.candidate_account_count = 1 and b.account_exists_in_crm then b.account_id end as account_id,
    case when p.candidate_account_count = 1 then b.mapping_source end      as mapping_source,
    case when p.candidate_account_count = 1 then b.mapping_confidence end  as mapping_confidence,
    coalesce(p.candidate_account_count, 0)                                  as candidate_account_count,
    p.candidate_account_ids,
    coalesce(p.candidate_account_count, 0) > 1                              as is_ambiguous,
    case
        when p.candidate_account_count is null           then 'unmapped'
        when p.candidate_account_count > 1               then 'ambiguous'
        when not b.account_exists_in_crm                 then 'broken_link'
        when b.mapping_confidence < 0.70                 then 'resolved_low_confidence'
        else 'resolved'
    end                                                                     as resolution_status
from orgs as o
left join per_org   as p on o.org_id = p.org_id
left join best_link as b on o.org_id = b.org_id
