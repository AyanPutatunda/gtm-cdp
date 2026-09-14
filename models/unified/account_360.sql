/*
  UNIFIED · Account 360 — the view a rep opens
  Grain: one row per Salesforce account (every account, even with no
  product or external footprint yet).

  Time windows: surface adoption reflects everything in the snapshot;
  activity counts and signals use the lookback window (var lookback_days).

  Reads as four blocks:
    1. WHO    CRM identity + gaps in it
    2. USING  product footprint, members, surfaces (with honest evidence levels)
    3. HAPPENING  external + product signals in the lookback window
    4. SO WHAT    action_reasons (plain-English), priority_rank (v0 ordering)
*/
with accounts as (
    select
        entity_id            as account_id,
        entity_name          as account_name,
        domain_key,
        linkedin_slug,
        name_key,
        ticker,
        ticker_exchange,
        ticker_symbol,
        is_missing_domain,
        is_missing_linkedin,
        has_no_match_keys,
        is_domain_shared
    from {{ ref('int_match_keys') }}
    where entity_type = 'account'
),

orgs as (
    select
        account_id,
        count(*)                                                        as product_orgs,
        {{ agg_list('org_id') }}                                        as product_org_ids,
        max(plan_rank)                                                  as best_plan_rank,
        min(mapping_confidence)                                         as weakest_org_link_confidence,
        max(case when resolution_status = 'resolved_low_confidence' then 1 else 0 end) = 1 as has_unverified_org_link
    from {{ ref('int_org_account_resolution') }}
    where account_id is not null
    group by account_id
),

adoption as (
    select
        account_id,
        max(known_members)                                                        as known_members,
        max(case when surface = 'ui'  then account_evidence_status end)           as ui_adoption,
        max(case when surface = 'sdk' then account_evidence_status end)           as sdk_adoption,
        max(case when surface = 'cli' then account_evidence_status end)           as cli_adoption,
        max(case when surface = 'mcp' then account_evidence_status end)           as mcp_adoption,
        max(case when surface = 'ui'  then members_usage_proven end)              as ui_members_proven,
        max(case when surface = 'sdk' then members_usage_proven end)              as sdk_members_proven,
        -- 'org' means the proof is trace ingestion or CI, not a named member
        max(case when surface = 'sdk' then evidence_level end)                    as sdk_evidence_level,
        -- the caveat travels with the number. A rep reading "sdk: usage_proven"
        -- must also see that SDK can't be separated from the CLI, and that CLI
        -- and MCP have no usage signal at all in this data.
        {{ agg_list("upper(surface) || ' — ' || honest_summary", separator=' | ') }} as adoption_in_plain_english
    from {{ ref('fct_account_surface_adoption') }}
    group by account_id
),

activity as (
    select
        account_id,
        count(distinct case when actor_type in ('human', 'unknown') and evidence_kind = 'usage'
                            then person_id end)                                   as active_members_in_lookback,
        sum(case when activity_type in ('experiment', 'dataset', 'prompt') then 1 else 0 end) as objects_created_in_lookback,
        sum(case when activity_type in ('experiment', 'dataset', 'prompt')
                  and actor_type = 'automation' then 1 else 0 end)                 as automated_objects_in_lookback,
        sum(case when surface = 'unknown' then 1 else 0 end)                      as objects_origin_unknown_in_lookback,
        max(activity_at)                                                          as last_product_activity_at
    from {{ ref('int_product_activity') }}
    where account_id is not null and is_in_lookback
    group by account_id
),

member_accounts as (
    select distinct account_id, person_id
    from {{ ref('int_memberships') }}
    where account_id is not null
),

multi_account_members as (
    -- people who also belong to ANOTHER account: their browser events stay unattributed
    select ma.account_id, count(*) as members_shared_with_other_accounts
    from member_accounts as ma
    inner join {{ ref('int_member_account_resolution') }} as p on ma.person_id = p.person_id
    where p.is_ambiguous
    group by ma.account_id
),

trace as (
    -- one definition of trace growth, owned by int_account_trace_trend
    select account_id, trace_gb_last_7d, trace_growth_7d
    from {{ ref('int_account_trace_trend') }}
),

external_companies as (
    select account_id, count(*) as external_companies_linked
    from {{ ref('int_signal_company_resolution') }}
    where resolution_status = 'resolved'
    group by account_id
),

pending_review as (
    -- Two different queues, kept apart on purpose:
    --   pending_review  a key pointed here but the record could NOT be
    --                   resolved safely (conflict, or no identifiers at all)
    --   awaiting_confirmation  the record DID resolve, to this account or to
    --                   its twin, but the company name contradicts the key,
    --                   so its signals are held until a steward confirms.
    -- Before this split, a 'confirm_match' company counted in neither and an
    -- account could show 0 records pending while carrying signals in review.
    select
        c.account_id,
        count(distinct case when r.next_action = 'steward_review' then c.company_id end) as external_records_pending_review,
        count(distinct case when r.next_action = 'confirm_match'  then c.company_id end) as external_records_awaiting_confirmation
    from {{ ref('int_signal_company_match_candidates') }} as c
    inner join {{ ref('int_signal_company_resolution') }} as r
        on c.company_id = r.company_id
    where r.next_action in ('steward_review', 'confirm_match')
    group by c.account_id
),

tech as (
    select account_id, {{ agg_list('product_name') }} as tech_stack
    from {{ ref('int_external_signals') }}
    where signal_type = 'tech_detected' and resolution_status = 'resolved'
    group by account_id
),

signals as (
    select
        account_id,
        sum(case when occurred_at is not null and not needs_review
                  and cast(occurred_at as date) >  {{ lookback_start() }}
                  and cast(occurred_at as date) <= {{ as_of_date() }} then 1 else 0 end) as signals_in_lookback,
        sum(case when is_actionable then 1 else 0 end)                                  as actionable_signals,
        sum(case when needs_review then 1 else 0 end)                                   as signals_needing_review,
        -- ordered by how strong the reason is, then how fresh: a rep reads
        -- left to right, so a 0.30 intent signal must not lead a 0.98 one
        {{ agg_list_ordered("case when is_actionable then headline end",
                            "signal_confidence desc, occurred_at desc, signal_id",
                            " | ") }}                                                    as action_reasons
    from {{ ref('fct_account_signals') }}
    group by account_id
),

latest_signal as (
    select account_id, headline as latest_signal_headline, occurred_at as latest_signal_at
    from {{ ref('fct_account_signals') }}
    where signal_source = 'external'
      and not needs_review                 -- a flagged headline is never shown as "latest"
    qualify row_number() over (partition by account_id order by occurred_at desc, signal_id) = 1
),

assembled as (
    select
        -- 1. WHO
        a.account_id,
        a.account_name,
        a.domain_key                                                        as crm_domain,
        a.linkedin_slug                                                     as crm_linkedin_slug,
        a.ticker,
        case
            when a.has_no_match_keys   then 'missing domain and LinkedIn'
            when a.is_missing_domain   then 'missing domain'
            when a.is_missing_linkedin then 'missing LinkedIn'
        end                                                                 as crm_identifier_gaps,
        a.is_domain_shared                                                  as crm_domain_shared_with_other_account,

        -- 2. USING
        coalesce(o.product_orgs, 0)                                         as product_orgs,
        o.product_org_ids,
        case o.best_plan_rank when 3 then 'enterprise' when 2 then 'pro' when 1 then 'free' end as best_plan,
        o.weakest_org_link_confidence,
        coalesce(o.has_unverified_org_link, false)                          as has_unverified_org_link,
        coalesce(ad.known_members, 0)                                       as known_members,
        coalesce(ac.active_members_in_lookback, 0)                          as active_members_in_lookback,
        coalesce(mm.members_shared_with_other_accounts, 0)                  as members_shared_with_other_accounts,
        ad.ui_adoption,
        ad.sdk_adoption,
        ad.sdk_evidence_level,
        ad.cli_adoption,
        ad.mcp_adoption,
        coalesce(ad.ui_members_proven, 0)                                   as ui_members_proven,
        coalesce(ad.sdk_members_proven, 0)                                  as sdk_members_proven,
        ad.adoption_in_plain_english,
        coalesce(ac.objects_created_in_lookback, 0)                         as objects_created_in_lookback,
        coalesce(ac.automated_objects_in_lookback, 0)                       as automated_objects_in_lookback,
        coalesce(ac.objects_origin_unknown_in_lookback, 0)                  as objects_origin_unknown_in_lookback,
        ac.last_product_activity_at,
        t.trace_gb_last_7d,
        t.trace_growth_7d,

        -- 3. HAPPENING
        coalesce(ec.external_companies_linked, 0)                           as external_companies_linked,
        coalesce(s.signals_in_lookback, 0)                                  as signals_in_lookback,
        ls.latest_signal_headline                                           as latest_external_headline,
        ls.latest_signal_at                                                 as latest_external_signal_at,
        te.tech_stack,
        coalesce(pr.external_records_pending_review, 0)                     as external_records_pending_review,
        coalesce(pr.external_records_awaiting_confirmation, 0)               as external_records_awaiting_confirmation,
        coalesce(s.signals_needing_review, 0)                               as signals_needing_review,

        -- 4. SO WHAT
        coalesce(s.actionable_signals, 0)                                   as actionable_signals,
        s.action_reasons
    from accounts as a
    left join orgs                  as o  on a.account_id = o.account_id
    left join adoption              as ad on a.account_id = ad.account_id
    left join activity              as ac on a.account_id = ac.account_id
    left join multi_account_members as mm on a.account_id = mm.account_id
    left join trace                 as t  on a.account_id = t.account_id
    left join external_companies    as ec on a.account_id = ec.account_id
    left join pending_review        as pr on a.account_id = pr.account_id
    left join tech                  as te on a.account_id = te.account_id
    left join signals               as s  on a.account_id = s.account_id
    left join latest_signal         as ls on a.account_id = ls.account_id
)

select
    *,
    -- v0 ordering: more actionable reasons first, then faster usage growth.
    -- Deliberately simple and explainable until outcome data can train weights (see MEMO Q6).
    row_number() over (
        order by actionable_signals desc, coalesce(trace_growth_7d, -1) desc, account_id
    )                                                                       as priority_rank
from assembled
