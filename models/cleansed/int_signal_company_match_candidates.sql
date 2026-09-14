/*
  CLEANSED · Every possible external -> account link, with the key that made it
  Grain: one row per (company, match_method, account).

  Three deterministic keys are tried independently. Name is recorded too,
  but ref_external_match_rules marks it can_resolve = false: it can only
  suggest a match for review.
*/
with companies as (
    select entity_id as company_id, domain_key as website_domain, second_domain_key as linkedin_domain, linkedin_slug, name_key
    from {{ ref('int_match_keys') }}
    where entity_type = 'company'
),

accounts as (
    select entity_id as account_id, domain_key, linkedin_slug, name_key
    from {{ ref('int_match_keys') }}
    where entity_type = 'account'
),

rules as (select * from {{ ref('ref_external_match_rules') }}),

-- UNION (not UNION ALL) so a company/method/account pair can only appear once
candidates as (
    select c.company_id, 'linkedin_slug' as match_method, c.linkedin_slug as matched_value, a.account_id
    from companies c join accounts a on c.linkedin_slug = a.linkedin_slug

    union
    select c.company_id, 'website_domain', c.website_domain, a.account_id
    from companies c join accounts a on c.website_domain = a.domain_key

    union
    select c.company_id, 'linkedin_domain', c.linkedin_domain, a.account_id
    from companies c join accounts a on c.linkedin_domain = a.domain_key

    union
    select c.company_id, 'company_name', c.name_key, a.account_id
    from companies c join accounts a on c.name_key = a.name_key
)

select
    c.company_id,
    c.match_method,
    c.matched_value,
    c.account_id,
    r.precedence,
    cast(r.base_confidence as double)                                       as base_confidence,
    cast(r.can_resolve as boolean)                                          as can_resolve,
    -- how many accounts does this one key point at for this company?
    count(*) over (partition by c.company_id, c.match_method)               as accounts_for_key,
    count(*) over (partition by c.company_id, c.match_method) = 1           as is_unique_for_key
from candidates as c
inner join rules as r
    on c.match_method = r.match_method
