-- RAW layer: clicks on "install / copy MCP command" in the docs. Browser events.
select
    nullif(trim(user_id), '')       as user_id,
    cast({{ keyword_column("timestamp") }} as timestamp)    as event_at,
    nullif(trim(action), '')        as action
from {{ ref('raw_docs_mcp_events') }}
