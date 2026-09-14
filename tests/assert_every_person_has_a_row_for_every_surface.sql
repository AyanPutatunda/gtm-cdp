/*
  fct_member_surface_activity promises that "no evidence" is an explicit row,
  never a missing one: every person gets a row for every surface, including
  the four they have never touched. A dashboard that joins to this fact must
  never lose a member because they happen to be quiet.

  Returns one row per person whose surface coverage is incomplete, and one
  summary row if the totals do not multiply out.
*/
with surfaces as (
    select count(distinct surface) as n from {{ ref('fct_member_surface_activity') }}
),

people as (
    select count(*) as n from {{ ref('int_member_account_resolution') }}
),

per_person as (
    select person_id, count(distinct surface) as surfaces_present
    from {{ ref('fct_member_surface_activity') }}
    group by person_id
),

incomplete as (
    select p.person_id, p.surfaces_present, s.n as surfaces_expected
    from per_person as p
    cross join surfaces as s
    where p.surfaces_present <> s.n
),

missing_people as (
    select
        cast('<people missing entirely>' as varchar) as person_id,
        (select count(*) from per_person)            as surfaces_present,
        people.n                                     as surfaces_expected
    from people
    where (select count(*) from per_person) <> people.n
)

select * from incomplete
union all
select * from missing_people
