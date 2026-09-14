-- RAW layer: web-app page views from Segment. user_id is null for anonymous visitors.
select
    nullif(trim(anonymous_id), '')  as anonymous_id,
    nullif(trim(user_id), '')       as user_id,
    cast({{ keyword_column("timestamp") }} as timestamp)    as viewed_at,
    nullif(trim(path), '')          as page_path
from {{ ref('raw_segment_pages') }}
