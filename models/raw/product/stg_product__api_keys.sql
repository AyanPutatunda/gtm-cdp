-- RAW layer: one row per API key. Only a hash is stored, never the secret.
select
    nullif(trim(id), '')            as api_key_id,
    nullif(trim(user_id), '')       as user_id,
    nullif(trim(org_id), '')        as org_id,
    nullif(trim(key_hash), '')      as key_hash,
    nullif(trim(name), '')          as key_name
from {{ ref('raw_api_keys') }}
