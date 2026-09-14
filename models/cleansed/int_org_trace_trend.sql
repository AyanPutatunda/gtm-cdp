/*
  CLEANSED · Org trace-ingestion trend
  Grain: one row per org that ingested traces.

  Trace volume is org x day with no user_id: it proves the ORG sends traces
  programmatically, but it can never be split across members or surfaces.

    gb_last_7d  = sum of the 7 days ending on the as-of date
    growth_7d   = as-of day vs the same org 7 days earlier, as a fraction
                  (0.41 = +41%). If that baseline day is missing, the
                  earliest day in the window is used and days_compared says so.
*/
with daily as (
    select
        org_id,
        activity_date,
        sum(ingested_gb) as ingested_gb      -- collapses any duplicate org/day rows
    from {{ ref('stg_product__trace_volume') }}
    where activity_date >= {{ dbt.dateadd('day', -7, as_of_date()) }}
      and activity_date <= {{ as_of_date() }}
    group by org_id, activity_date
),

bounds as (
    select
        org_id,
        min(activity_date)                                                        as baseline_day,
        max(activity_date)                                                        as last_day,
        sum(case when activity_date > {{ dbt.dateadd('day', -7, as_of_date()) }}
                 then ingested_gb else 0 end)                                     as gb_last_7d,
        sum(case when activity_date > {{ dbt.dateadd('day', -7, as_of_date()) }}
                 then 1 else 0 end)                                               as days_with_data
    from daily
    group by org_id
)

select
    b.org_id,
    b.baseline_day,
    b.last_day,
    {{ dbt.datediff('b.baseline_day', 'b.last_day', 'day') }}      as days_compared,
    b.days_with_data,
    round(b.gb_last_7d, 2)                                         as gb_last_7d,
    f.ingested_gb                                                  as gb_baseline_day,
    l.ingested_gb                                                  as gb_last_day,
    case when f.ingested_gb > 0
         then round((l.ingested_gb - f.ingested_gb) / f.ingested_gb, 4) end as growth_7d
from bounds as b
inner join daily as f on b.org_id = f.org_id and b.baseline_day = f.activity_date
inner join daily as l on b.org_id = l.org_id and b.last_day     = l.activity_date
