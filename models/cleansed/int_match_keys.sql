/*
  CLEANSED · Match keys
  Grain: one row per matchable entity — every Salesforce account and every
  external company, side by side.

  This is the ONLY place identifiers are normalised. Both sides go through
  the same CTEs below, so a key built from Salesforce and a key built from
  the vendor feed can never drift apart. It is plain SQL on purpose: lower,
  trim, strip, split. No regex, no macros to look up.

  What each step does. The first line is the shape the brief calls out;
  the rest are real values from the seeds:

    scheme      'https://www.Acme.com/products?utm=x' -> 'www.acme.com/products?utm=x'
    www         'www.acme.com/products?utm=x'         -> 'acme.com/products?utm=x'
    first /?#:  'acme.com/products?utm=x'             -> 'acme.com'
    trailing .  'acme.com.'                           -> 'acme.com'

    linkedin    '.../company/pied-piper/'             -> 'pied-piper'
                (works for any scheme, www, or country sub-domain, because we
                 only keep what sits between '/company/' and the next / ? #)

    name        'Acme Corporation'       -> 'acme'
                'Wayne Enterprises Inc.' -> 'wayneenterprises'
                'PiedPiper' = 'Pied Piper' -> 'piedpiper'
                The name key is a review hint only. It never decides a match.

    token       'Wayne Enterprises Inc.' -> 'wayne'
                The leading word of the cleaned name. Used by
                int_external_signals to check that a headline actually names
                the company it is keyed to. It lives here, not there, because
                the project has exactly one place that normalises a name.
*/
with entities as (

    -- Salesforce side
    select
        'account'                       as entity_type,
        account_id                      as entity_id,
        account_name                    as entity_name,
        domain                          as website_raw,
        linkedin_company_url            as linkedin_raw,
        cast(null as varchar)           as second_domain_raw,
        ticker
    from {{ ref('stg_crm__salesforce_accounts') }}

    union all

    -- external feed side
    select
        'company',
        company_id,
        company_name,
        company_website,
        linkedin_url,
        linkedin_domain,                -- the website LinkedIn reports for the company
        cast(null as varchar)
    from {{ ref('stg_signals__companies') }}
),

lowered as (
    select
        entity_type,
        entity_id,
        entity_name,
        ticker,
        lower(trim(website_raw))        as website_lc,
        lower(trim(linkedin_raw))       as linkedin_lc,
        lower(trim(second_domain_raw))  as second_domain_lc,
        lower(trim(entity_name))        as name_lc
    from entities
),

-- 1. domains: drop the scheme, then 'www.', then anything from the first / ? # :
no_scheme as (
    select
        lowered.*,
        replace(replace(website_lc,       'https://', ''), 'http://', '')  as website_1,
        replace(replace(second_domain_lc, 'https://', ''), 'http://', '')  as second_1
    from lowered
),

no_www as (
    select
        no_scheme.*,
        case when left(website_1, 4) = 'www.' then substr(website_1, 5) else website_1 end as website_2,
        case when left(second_1,  4) = 'www.' then substr(second_1,  5) else second_1  end as second_2
    from no_scheme
),

host_only as (
    select
        no_www.*,
        split_part(split_part(split_part(split_part(website_2, '/', 1), '?', 1), '#', 1), ':', 1) as website_3,
        split_part(split_part(split_part(split_part(second_2,  '/', 1), '?', 1), '#', 1), ':', 1) as second_3
    from no_www
),

domains as (
    select
        host_only.*,
        nullif(case when right(website_3, 1) = '.' then left(website_3, greatest(0, length(website_3) - 1)) else website_3 end, '') as domain_key,
        nullif(case when right(second_3,  1) = '.' then left(second_3, greatest(0, length(second_3) - 1)) else second_3  end, '') as second_domain_key
    from host_only
),

-- 2. LinkedIn: keep what sits between '/company/' and the next / ? #
linkedin as (
    select
        domains.*,
        nullif(
            split_part(split_part(split_part(split_part(linkedin_lc, '/company/', 2), '/', 1), '?', 1), '#', 1),
            ''
        ) as linkedin_slug
    from domains
),

-- 3. name: drop punctuation, drop a trailing legal suffix, close up the spaces
name_cleaned as (
    select
        linkedin.*,
        trim(
            replace(replace(replace(replace(replace(replace(name_lc,
                '.', ''), ',', ''), '(', ''), ')', ''), '-', ' '), '''', '')
        ) as name_words
    from linkedin
),

name_no_suffix as (
    select
        name_cleaned.*,
        trim(case
            when name_words like '% incorporated' then left(name_words, greatest(0, length(name_words) - 13))
            when name_words like '% corporation'  then left(name_words, greatest(0, length(name_words) - 12))
            when name_words like '% company'      then left(name_words, greatest(0, length(name_words) - 8))
            when name_words like '% limited'      then left(name_words, greatest(0, length(name_words) - 8))
            when name_words like '% gmbh'         then left(name_words, greatest(0, length(name_words) - 5))
            when name_words like '% corp'         then left(name_words, greatest(0, length(name_words) - 5))
            when name_words like '% inc'          then left(name_words, greatest(0, length(name_words) - 4))
            when name_words like '% llc'          then left(name_words, greatest(0, length(name_words) - 4))
            when name_words like '% ltd'          then left(name_words, greatest(0, length(name_words) - 4))
            when name_words like '% plc'          then left(name_words, greatest(0, length(name_words) - 4))
            when name_words like '% co'           then left(name_words, greatest(0, length(name_words) - 3))
            else name_words
        end) as name_trimmed
    from name_cleaned
),

keyed as (
    select
        entity_type,
        entity_id,
        entity_name,
        domain_key,
        second_domain_key,
        linkedin_slug,
        nullif(replace(name_trimmed, ' ', ''), '')                                  as name_key,
        nullif(split_part(name_trimmed, ' ', 1), '')                                as name_first_token,
        upper(ticker)                                                               as ticker,
        case when ticker like '%:%' then upper(split_part(ticker, ':', 1)) end      as ticker_exchange,
        case when ticker like '%:%' then upper(split_part(ticker, ':', 2))
             else upper(ticker) end                                                 as ticker_symbol
    from name_no_suffix
)

select
    entity_type,
    entity_id,
    entity_name,
    domain_key,
    second_domain_key,
    linkedin_slug,
    name_key,
    name_first_token,
    -- a token under 4 characters ('the', 'ai', 'co') matches almost any
    -- headline, so the entity check downstream skips it rather than pretend
    length(coalesce(name_first_token, '')) >= 4                                     as name_token_is_specific,
    ticker,
    ticker_exchange,
    ticker_symbol,
    domain_key is null                                                              as is_missing_domain,
    linkedin_slug is null                                                           as is_missing_linkedin,
    domain_key is null and linkedin_slug is null                                    as has_no_match_keys,
    -- a key shared by two rows on the same side can support a match, never decide one
    case when domain_key is not null
         then count(*) over (partition by entity_type, domain_key) > 1
         else false end                                                             as is_domain_shared,
    case when linkedin_slug is not null
         then count(*) over (partition by entity_type, linkedin_slug) > 1
         else false end                                                             as is_linkedin_shared
from keyed
