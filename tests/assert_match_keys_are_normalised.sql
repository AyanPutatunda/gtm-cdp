/*
  The normaliser, pinned to every row we have.

  Each expected value below was read off the seed CSV by hand, so this test
  fails if the plain-SQL normalisation in int_match_keys ever changes shape:
  a scheme left on, a 'www.' kept, a trailing slash, a query string, a legal
  suffix that stops being stripped.

  Returns one row per mismatch.
*/
with expected (entity_type, entity_id, domain_key, linkedin_slug, name_key) as (
    select 'account', 'ACC001', 'acme.com',              'acme-corp',         'acme'             union all
    select 'account', 'ACC002', null,                    'globex-industries', 'globex'           union all
    select 'account', 'ACC003', 'initech.com',           null,                'initech'          union all
    select 'account', 'ACC004', 'umbrella.co',           'umbrella-labs',     'umbrellalabs'     union all
    select 'account', 'ACC005', 'soylent.com',           null,                'soylent'          union all
    select 'account', 'ACC006', 'hooli.com',             'hooli',             'hooli'            union all
    select 'account', 'ACC007', 'hooli.com',             'hooli-xyz',         'hoolixyz'         union all
    select 'account', 'ACC008', null,                    null,                'starkindustries'  union all
    select 'account', 'ACC009', 'wayne.com',             'wayne-ent',         'wayneenterprises' union all
    select 'account', 'ACC010', 'piedpiper.com',         'pied-piper',        'piedpiper'        union all
    select 'company', 'sc01',   'acme.com',              'acme-corp',         'acme'             union all
    select 'company', 'sc02',   'globex.io',             'globex-industries', 'globex'           union all
    select 'company', 'sc03',   'initech.com',           'initech-software',  'initech'          union all
    select 'company', 'sc04',   'umbrella.co',           'umbrella-labs',     'umbrella'         union all
    select 'company', 'sc05',   'hooli.com',             'hooli-xyz',         'hooli'            union all
    select 'company', 'sc06',   'hooli.com',             'hooli',             'hooli'            union all
    select 'company', 'sc07',   null,                    null,                'starkindustries'  union all
    select 'company', 'sc08',   'wayne-enterprises.com', 'wayne-ent',         'wayneenterprises' union all
    select 'company', 'sc09',   'piedpiper.com',         'pied-piper',        'piedpiper'        union all
    select 'company', 'sc10',   'prospect-ai.com',       'prospect-ai',       'prospectai'       union all
    select 'company', 'sc11',   'acme.com',              'pied-piper',        'acmeduprecord'
)

select
    e.entity_type,
    e.entity_id,
    e.domain_key      as expected_domain,   k.domain_key    as actual_domain,
    e.linkedin_slug   as expected_linkedin, k.linkedin_slug as actual_linkedin,
    e.name_key        as expected_name,     k.name_key      as actual_name
from expected as e
left join {{ ref('int_match_keys') }} as k
    on e.entity_type = k.entity_type
   and e.entity_id   = k.entity_id
where coalesce(k.domain_key,    '~') <> coalesce(e.domain_key,    '~')
   or coalesce(k.linkedin_slug, '~') <> coalesce(e.linkedin_slug, '~')
   or coalesce(k.name_key,      '~') <> coalesce(e.name_key,      '~')
