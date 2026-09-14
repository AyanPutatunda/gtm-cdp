-- RAW layer: third-party company records. No Salesforce id: only a messy
-- website, a LinkedIn URL and a LinkedIn-reported domain.
select
    nullif(trim(company_id), '')        as company_id,
    nullif(trim(company_name), '')      as company_name,
    nullif(trim(company_website), '')   as company_website,
    nullif(trim(linkedin_url), '')      as linkedin_url,
    nullif(trim(linkedin_domain), '')   as linkedin_domain
from {{ ref('raw_signal_companies') }}
