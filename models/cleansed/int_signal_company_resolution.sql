/*
  CLEANSED · External company -> Salesforce account (the CDP core)
  Grain: one row per external company. Nothing is dropped.

  Precedence (ref_external_match_rules)
    1. linkedin_slug    0.90   one page per legal entity
    2. website_domain   0.85   strong, but shared by parents/subsidiaries
    3. linkedin_domain  0.75   self-reported on LinkedIn
    -  company_name     never resolves; suggestion for review only

  How a winner is chosen
    - Only keys that point at exactly ONE account can decide.
    - The highest-precedence deciding key wins.
    - Every other key that matched must AGREE (its accounts include the
      winner). If any key points somewhere else -> conflict, no account.
    - Two or more INDEPENDENT deciding keys agreeing -> +0.05 (capped 0.99).
      The same value in two vendor fields (initech.com twice) counts once.
    - A name that uniquely points at a DIFFERENT account (sc05 'Hooli Inc'
      vs LinkedIn hooli-xyz) does not decide anything, but it is
      contradicting evidence: confidence -0.20 and needs_review = true, so
      its signals wait for a steward instead of reaching a rep.

  Outcomes
    resolved        -> attach signals to the account
    conflict        -> keys disagree (sc11: acme.com says ACC001,
                       LinkedIn 'pied-piper' says ACC010) -> steward review
    ambiguous       -> only shared keys matched -> steward review
    unmatched       -> has keys, no account -> net-new prospect
    no_identifiers  -> nothing to match on (sc07) -> enrich / review
*/
with companies as (
    select
        entity_id            as company_id,
        entity_name          as company_name,
        domain_key           as website_domain,
        second_domain_key    as linkedin_domain,
        linkedin_slug,
        name_key,
        coalesce(domain_key, linkedin_slug, second_domain_key) is not null as has_any_key,
        is_domain_shared     as is_website_shared_in_feed
    from {{ ref('int_match_keys') }}
    where entity_type = 'company'
),

deciding as (           -- keys allowed to resolve (not name)
    select * from {{ ref('int_signal_company_match_candidates') }}
    where can_resolve
),

winner as (
    select company_id, match_method as winning_method, account_id as winning_account_id, base_confidence
    from deciding
    where is_unique_for_key
    qualify row_number() over (partition by company_id order by precedence, account_id) = 1
),

key_summary as (
    select
        d.company_id,
        count(distinct d.match_method)                                                        as keys_matched,
        count(distinct case when d.account_id = w.winning_account_id then d.match_method end) as keys_agreeing,
        -- independent evidence = distinct VALUES, so initech.com seen in two vendor fields counts once
        count(distinct case when d.account_id = w.winning_account_id and d.is_unique_for_key
                            then d.matched_value end)                                         as unique_keys_agreeing,
        {{ agg_list("d.match_method || '=' || d.matched_value || ' -> ' || d.account_id") }}  as match_evidence,
        {{ agg_list('d.account_id') }}                                                        as candidate_account_ids
    from deciding as d
    left join winner as w
        on d.company_id = w.company_id
    group by d.company_id
),

name_hint as (
    select company_id, account_id as name_match_account_id
    from {{ ref('int_signal_company_match_candidates') }}
    where match_method = 'company_name' and is_unique_for_key
),

classified as (
    select
        c.company_id,
        c.company_name,
        c.website_domain,
        c.linkedin_slug,
        c.linkedin_domain,
        c.has_any_key,
        c.is_website_shared_in_feed,
        coalesce(k.keys_matched, 0)                          as keys_matched,
        coalesce(k.keys_agreeing, 0)                         as keys_agreeing,
        coalesce(k.unique_keys_agreeing, 0)                  as unique_keys_agreeing,
        k.match_evidence,
        k.candidate_account_ids,
        w.winning_method,
        w.winning_account_id,
        w.base_confidence,
        n.name_match_account_id,
        coalesce(n.name_match_account_id <> w.winning_account_id, false)   as name_contradicts,
        case
            when not c.has_any_key                                   then 'no_identifiers'
            when k.company_id is null                                then 'unmatched'
            when w.company_id is null                                then 'ambiguous'
            when k.keys_matched > k.keys_agreeing                    then 'conflict'
            else 'resolved'
        end                                                  as resolution_status
    from companies as c
    left join key_summary as k on c.company_id = k.company_id
    left join winner      as w on c.company_id = w.company_id
    left join name_hint   as n on c.company_id = n.company_id
)

select
    company_id,
    company_name,
    website_domain,
    linkedin_slug,
    linkedin_domain,
    resolution_status,
    case when resolution_status = 'resolved' then winning_account_id end        as account_id,
    case when resolution_status = 'resolved' then winning_method end            as match_method,
    case when resolution_status = 'resolved'
         then round(least(0.99, base_confidence
                                + case when unique_keys_agreeing >= 2 then 0.05 else 0 end
                                - case when name_contradicts then 0.20 else 0 end), 2)
    end                                                                         as match_confidence,
    coalesce(resolution_status = 'resolved' and name_contradicts, false)        as needs_review,
    resolution_status = 'conflict'                                              as is_conflict,
    keys_matched,
    keys_agreeing,
    unique_keys_agreeing,
    match_evidence,
    candidate_account_ids,
    name_match_account_id,
    case when resolution_status = 'resolved'
         then coalesce(name_match_account_id = winning_account_id, false) end   as name_agrees_with_match,
    is_website_shared_in_feed,
    case
        when resolution_status = 'resolved' and name_contradicts                then 'confirm_match'
        when resolution_status = 'resolved'                                     then 'attach_to_account'
        when resolution_status in ('conflict', 'ambiguous')                     then 'steward_review'
        when name_match_account_id is not null                                  then 'steward_review'
        when resolution_status = 'unmatched'                                    then 'net_new_prospect'
        else 'enrich_identifiers'
    end                                                                         as next_action
from classified
