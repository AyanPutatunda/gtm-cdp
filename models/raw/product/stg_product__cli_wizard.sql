-- RAW layer: CLI *setup wizard* events. These fire in the browser, not the CLI.
select
    nullif(trim(user_id), '')       as user_id,
    cast({{ keyword_column("timestamp") }} as timestamp)    as event_at
from {{ ref('raw_cli_wizard') }}
