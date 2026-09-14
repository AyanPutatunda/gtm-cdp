-- RAW layer: one row per product the vendor detected.
select
    nullif(trim(id), '')                as product_id,
    nullif(trim(company_id), '')        as company_id,
    nullif(trim(name), '')              as product_name,
    nullif(trim(category), '')          as category,
    cast(first_seen_at as timestamp)      as first_seen_at,
    nullif(trim(source_url), '')        as source_url
from {{ ref('raw_products') }}
