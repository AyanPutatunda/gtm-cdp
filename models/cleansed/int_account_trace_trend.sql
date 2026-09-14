/*
  CLEANSED · Account trace-ingestion trend
  Grain: one row per Salesforce account that has at least one org sending
  traces.

  This model exists for one reason: the same arithmetic used to live in
  three places (fct_account_surface_adoption, fct_account_signals and
  account_360 each rolled int_org_trace_trend up to the account and
  recomputed the growth ratio). They agreed, but nothing stopped them
  drifting. Growth is now computed once, here, and read three times.

  Trace volume is org x day with no user_id, so everything below is
  ACCOUNT-level evidence and can never be split across members or surfaces.
*/
with org_trend as (
    select * from {{ ref('int_org_trace_trend') }}
),

orgs as (
    select org_id, account_id
    from {{ ref('int_org_account_resolution') }}
    where account_id is not null
),

joined as (
    select
        o.account_id,
        t.org_id,
        t.gb_last_7d,
        t.gb_baseline_day,
        t.gb_last_day,
        t.last_day
    from org_trend as t
    inner join orgs as o
        on t.org_id = o.org_id
)

select
    account_id,
    count(distinct org_id)                                            as orgs_sending_traces,
    {{ agg_list('org_id') }}                                          as org_ids_sending_traces,
    round(sum(gb_last_7d), 2)                                         as trace_gb_last_7d,
    sum(gb_baseline_day)                                              as gb_baseline_day,
    sum(gb_last_day)                                                  as gb_last_day,
    max(last_day)                                                     as last_day,
    -- unrounded inputs, rounded result: the one definition of "trace growth"
    case when sum(gb_baseline_day) > 0
         then round((sum(gb_last_day) - sum(gb_baseline_day)) / sum(gb_baseline_day), 4) end
                                                                      as trace_growth_7d,
    coalesce(
        case when sum(gb_baseline_day) > 0
             then (sum(gb_last_day) - sum(gb_baseline_day)) / sum(gb_baseline_day) end
        >= {{ var('usage_surge_threshold') }}, false)                 as is_usage_surge
from joined
group by account_id
