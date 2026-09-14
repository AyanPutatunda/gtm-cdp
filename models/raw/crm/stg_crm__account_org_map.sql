-- RAW layer: product org -> Salesforce account, with how the link was made.
select
    nullif(trim(org_id), '')                as org_id,
    nullif(trim(account_id), '')            as account_id,
    nullif(trim(mapping_source), '')        as mapping_source
from {{ ref('raw_account_org_map') }}
