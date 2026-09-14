/*
  Part B: "Keep any unresolved companies. A CDP does not silently drop them."

  Every external company must leave the platform through exactly one door:

    attach_to_account  the match is safe — its signals reach the rep
    confirm_match      matched, but something disagrees — held for a steward
    steward_review     unresolved, and an account may well already exist
                       (a conflict, or no identifiers at all) — so calling it
                       "net new" would be wrong
    net_new_prospect   unresolved, and no account can exist for it — an output,
                       not an error

  This test fails if a company reaches none of them, or more than one.
*/
with doors as (
    select
        c.company_id,
        case when c.next_action = 'net_new_prospect' then 1 else 0 end
            + case when c.next_action = 'steward_review' then 1 else 0 end
            + case when c.next_action = 'confirm_match' then 1 else 0 end
            + case when c.next_action = 'attach_to_account' then 1 else 0 end   as doors_taken,
        case when p.prospect_id is not null then 1 else 0 end                    as in_prospect_list,
        case when c.next_action = 'net_new_prospect' then 1 else 0 end           as should_be_in_prospect_list
    from {{ ref('dim_signal_companies') }} as c
    left join {{ ref('net_new_prospects') }} as p
        on p.prospect_id = 'external:' || c.company_id
)

select company_id, doors_taken, in_prospect_list, should_be_in_prospect_list
from doors
where doors_taken <> 1
   or in_prospect_list <> should_be_in_prospect_list
