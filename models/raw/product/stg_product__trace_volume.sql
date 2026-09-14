-- RAW layer: org x day ingestion volume. There is no user_id at this grain.
select
    nullif(trim(org_id), '')                as org_id,
    cast(ds as date)                          as activity_date,
    cast(ingested_gb as double)               as ingested_gb
from {{ ref('raw_trace_volume') }}
