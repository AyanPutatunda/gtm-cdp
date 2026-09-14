-- RAW layer: Salesforce accounts. domain and linkedin_company_url are sometimes null.
select
    nullif(trim(account_id), '')            as account_id,
    nullif(trim(account_name), '')          as account_name,
    nullif(trim(domain), '')                as domain,
    nullif(trim(linkedin_company_url), '')  as linkedin_company_url,
    nullif(trim(ticker), '')                as ticker
from {{ ref('raw_salesforce_accounts') }}
