/*
  CLEANSED · User identity
  Grain: one row per product login (user_id).

  Decisions
  - Emails are matched case-insensitively (lower + trim).
  - Two logins with the exact same email address are the same person: the
    inbox is the identity. We keep BOTH user_ids and point them at one
    person_id (the earliest login), so nothing is lost and counts of
    "people" are not inflated. Found in the seeds: u_grace + u_grace_dup.
  - We do NOT merge on anything fuzzier (same name, same domain). That would
    be a guess, and a bad merge is worse than an unmerged pair.
*/
with users as (
    select
        user_id,
        email,
        lower(trim(email))                                as email_normalized,
        split_part(lower(trim(email)), '@', 2)            as email_domain,
        created_at
    from {{ ref('stg_product__users') }}
    -- exact-duplicate guard: one row per user_id
    qualify row_number() over (partition by user_id order by created_at) = 1
),

grouped as (
    select
        *,
        first_value(user_id) over (
            partition by coalesce(email_normalized, user_id)
            order by created_at, user_id
        )                                                              as person_id,
        count(*) over (partition by coalesce(email_normalized, user_id)) as logins_for_person
    from users
)

select
    user_id,
    person_id,
    email,
    email_normalized,
    email_domain,
    created_at,
    logins_for_person,
    logins_for_person > 1                                   as is_duplicate_login,
    user_id <> person_id                                    as is_secondary_login,
    case when logins_for_person > 1 then 'exact_email_match'
         else 'single_login' end                            as person_resolution_method
from grouped
