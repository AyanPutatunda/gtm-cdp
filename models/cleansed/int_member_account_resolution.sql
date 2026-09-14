/*
  CLEANSED · Person -> account
  Grain: one row per person (deduplicated human, see int_user_identity).

  Path: login -> person, login -> org membership, org -> account.

  Decisions
  - A person whose orgs all roll up to ONE account resolves to it
    (e.g. Alice: org_acme + org_acme_eu -> ACC001).
  - A person with one mapped org AND an unmapped org is 'partially_mapped':
    their browser events could belong to either, so no single account.
  - Account confidence is the WEAKEST org link behind it (conservative).
  - A person in orgs belonging to DIFFERENT accounts is flagged
    ambiguous and gets no single account (e.g. Frank: Globex + Umbrella).
    Their project-scoped activity is still attributed correctly later,
    because objects carry a project -> org. Only their browser events
    (which have no org) stay unattributed.
*/
with identity as (
    select * from {{ ref('int_user_identity') }}
),

memberships as (
    select * from {{ ref('int_memberships') }}
),

people as (
    select
        person_id,
        max(email_normalized)                        as email,
        max(email_domain)                            as email_domain,
        count(*)                                     as login_count,
        {{ agg_list('user_id') }}                    as user_ids,
        min(created_at)                              as first_login_created_at
    from identity
    group by person_id
),

per_person as (
    select
        person_id,
        count(distinct org_id)                                           as org_count,
        {{ agg_list('org_id') }}                                         as org_ids,
        count(distinct account_id)                                       as account_count,
        {{ agg_list('account_id') }}                                     as account_ids,
        sum(case when account_id is null then 1 else 0 end)              as unmapped_org_count,
        min(mapping_confidence)                                          as weakest_mapping_confidence
    from memberships
    group by person_id
)

select
    p.person_id,
    p.email,
    p.email_domain,
    p.login_count,
    p.user_ids,
    p.first_login_created_at,
    coalesce(m.org_count, 0)                                  as org_count,
    m.org_ids,
    coalesce(m.account_count, 0)                              as account_count,
    m.account_ids                                             as candidate_account_ids,
    case when m.account_count = 1 and m.unmapped_org_count = 0 then m.account_ids end              as account_id,
    case when m.account_count = 1 and m.unmapped_org_count = 0 then m.weakest_mapping_confidence end as account_confidence,
    coalesce(m.unmapped_org_count, 0) > 0                     as has_unmapped_org,
    coalesce(m.account_count, 0) > 1                          as is_ambiguous,
    case
        when m.person_id is null        then 'no_membership'
        when m.account_count = 0        then 'org_not_mapped'
        when m.account_count > 1        then 'ambiguous_multi_account'
        when m.unmapped_org_count > 0   then 'partially_mapped'
        else 'resolved'
    end                                                       as resolution_status
from people as p
left join per_person as m
    on p.person_id = m.person_id
