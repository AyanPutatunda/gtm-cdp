/*
  CLEANSED · API keys
  Grain: one row per API key, pointed at a person and an org.

  Key names are free text, so they are only ever hints:
    'cli'         in the name -> CLI intent hint
    'ci' / 'service' / 'bot'  -> the key is probably used by automation
  Objects do not record which key created them (see MEMO Q4), so these
  hints never attribute an object to a surface on their own.
*/
select
    k.api_key_id,
    i.person_id,
    k.user_id,
    k.org_id,
    k.key_hash,
    k.key_name,
    lower(k.key_name) like '%cli%'                                        as is_cli_named,
    lower(k.key_name) like 'ci-%' or lower(k.key_name) like '%-ci'
        or lower(k.key_name) like '%service%' or lower(k.key_name) like '%bot%' as is_automation_named
from {{ ref('stg_product__api_keys') }} as k
left join {{ ref('int_user_identity') }} as i
    on k.user_id = i.user_id
qualify row_number() over (partition by k.api_key_id order by k.key_hash) = 1
