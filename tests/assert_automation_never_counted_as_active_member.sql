/*
  A login whose only activity is automation (Bob's CI key) must not make an
  account look like it has more active people. For every account, active
  members in account_360 can be at most the known members who are NOT
  automation identities. Returns accounts that break this.
*/
with automation_members as (
    select m.account_id, count(distinct m.person_id) as automation_identities
    from {{ ref('int_memberships') }} as m
    inner join {{ ref('dim_members') }} as d
        on m.person_id = d.person_id
    where d.member_type = 'automation_identity'
      and m.account_id is not null
    group by m.account_id
)

select
    a.account_id,
    a.known_members,
    coalesce(x.automation_identities, 0) as automation_identities,
    a.active_members_in_lookback
from {{ ref('account_360') }} as a
left join automation_members as x
    on a.account_id = x.account_id
where a.active_members_in_lookback > a.known_members - coalesce(x.automation_identities, 0)
