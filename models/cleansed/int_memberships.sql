/*
  CLEANSED · Memberships
  Grain: one row per person x org.

  raw_members is login x org. After logins are collapsed into people
  (u_grace + u_grace_dup), the same person can appear twice in one org;
  this model deduplicates that and attaches the org's account resolution,
  so nothing downstream has to read raw memberships again.
*/
with memberships as (
    select
        i.person_id,
        m.org_id,
        min(m.member_created_at)                        as first_member_created_at,
        count(*)                                        as logins_in_org
    from {{ ref('stg_product__members') }} as m
    inner join {{ ref('int_user_identity') }} as i
        on m.user_id = i.user_id
    group by i.person_id, m.org_id
)

select
    m.person_id,
    m.org_id,
    m.first_member_created_at,
    m.logins_in_org,
    o.account_id,
    o.resolution_status                                 as org_resolution_status,
    o.mapping_confidence
from memberships as m
left join {{ ref('int_org_account_resolution') }} as o
    on m.org_id = o.org_id
