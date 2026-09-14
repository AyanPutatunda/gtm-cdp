-- RAW layer: one row per technology detected on a company's stack.
select
    nullif(trim(id), '')                as detection_id,
    nullif(trim(company_id), '')        as company_id,
    nullif(trim(technology_name), '')   as technology_name,
    cast(first_seen_at as timestamp)      as first_seen_at,
    cast(score as double)                 as vendor_score
from {{ ref('raw_tech_detections') }}
