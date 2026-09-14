-- RAW layer: one row per news event detected by the vendor.
select
    nullif(trim(id), '')                as news_id,
    nullif(trim(company_id), '')        as company_id,
    nullif(trim(category), '')          as category,
    nullif(trim(summary), '')           as summary,
    cast(found_at as timestamp)           as found_at,
    cast(confidence as double)            as vendor_confidence,
    nullif(trim(product_name), '')      as product_name,
    nullif(trim(source_url), '')        as source_url
from {{ ref('raw_news_events') }}
