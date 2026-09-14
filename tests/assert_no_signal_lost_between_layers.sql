/*
  Every raw external record (news + products + tech) must survive into the
  signal stream, except product detections that repeat a news launch for
  the same company and product. Returns a row if the counts don't reconcile.
*/
with raw_count as (
    select
        (select count(*) from {{ ref('stg_signals__news_events') }})
      + (select count(*) from {{ ref('stg_signals__products') }})
      + (select count(*) from {{ ref('stg_signals__tech_detections') }}) as n
),

expected_merges as (
    select count(*) as n
    from {{ ref('stg_signals__products') }} as p
    where exists (
        select 1
        from {{ ref('stg_signals__news_events') }} as e
        where e.company_id = p.company_id
          and lower(e.category) = 'launches'
          and lower(trim(e.product_name)) = lower(trim(p.product_name))
    )
),

kept as (
    select count(*) as n from {{ ref('int_external_signals') }}
)

select raw_count.n as raw_rows, kept.n as kept_rows, expected_merges.n as merged_duplicates
from raw_count cross join kept cross join expected_merges
where raw_count.n <> kept.n + expected_merges.n
