/*
  CLEANSED · External signals, one stream
  Grain: one row per distinct external signal (news, product, tech).

  Decisions
  - News, detected products and tech detections become one shape so the
    UNIFIED layer can treat them alike (and a 4th feed is one more union).
  - Cross-source duplicates are removed: "Acme launches Acme Copilot" (news)
    and "Acme Copilot" (product detection) are the same fact. We keep the
    news row and mark it corroborated instead of showing it twice.
  - Entity check: if a headline does not mention the company it is keyed to,
    we flag it. Deliberately simple: the leading word of the NORMALISED vendor
    name (int_match_keys.name_first_token — this model does not normalise a
    name of its own) must appear in the headline. Cheap, catches key-swaps,
    can't split Hooli from Hooli XYZ. A token under 4 characters is too
    generic to test with, so the check is skipped and the row is not flagged.
    Found in the seeds: n5 is keyed to Wayne (sc08) but reads
    "Stark Industries hires new CTO". Flagged rows are never actionable.
  - Resolution (account, method, confidence) is carried on every row, so a
    rep can always see WHY a signal landed on their account.
*/
with companies as (
    select
        c.company_id,
        c.company_name,
        -- 'Wayne Enterprises Inc.' -> 'wayne', built by the one normaliser
        k.name_first_token                            as name_token,
        k.name_token_is_specific
    from {{ ref('stg_signals__companies') }} as c
    left join {{ ref('int_match_keys') }} as k
        on  k.entity_type = 'company'
        and k.entity_id   = c.company_id
),

news as (
    select
        'news:' || news_id                               as signal_id,
        news_id                                          as source_record_id,
        company_id,
        'news'                                           as signal_family,
        lower(category)                                  as signal_type,
        summary                                          as headline,
        product_name,
        found_at                                         as occurred_at,
        vendor_confidence,
        source_url
    from {{ ref('stg_signals__news_events') }}
),

products as (
    select
        'product:' || product_id,
        product_id,
        company_id,
        'product',
        'product_detected',
        'New product detected: ' || product_name,
        product_name,
        first_seen_at,
        cast(null as double),
        source_url
    from {{ ref('stg_signals__products') }}
),

tech as (
    select
        'tech:' || detection_id,
        detection_id,
        company_id,
        'tech',
        'tech_detected',
        'Uses ' || technology_name,
        technology_name,
        first_seen_at,
        vendor_score,
        cast(null as varchar)
    from {{ ref('stg_signals__tech_detections') }}
),

unioned as (
    select * from news
    union all select * from products
    union all select * from tech
),

-- a product detection that repeats a launch already in the news
launch_duplicates as (
    select distinct p.signal_id as duplicate_signal_id, n.signal_id as kept_signal_id
    from unioned as p
    inner join unioned as n
        on  p.company_id = n.company_id
        and p.signal_family = 'product'
        and n.signal_family = 'news'
        and n.signal_type   = 'launches'
        and lower(trim(p.product_name)) = lower(trim(n.product_name))
),

deduped as (
    select u.*
    from unioned as u
    left join launch_duplicates as d
        on u.signal_id = d.duplicate_signal_id
    where d.duplicate_signal_id is null
    -- exact duplicates of the same record
    qualify row_number() over (partition by u.signal_id order by u.occurred_at) = 1
),

resolution as (
    select company_id, account_id, resolution_status, match_method, match_confidence, needs_review
    from {{ ref('int_signal_company_resolution') }}
)

select
    s.signal_id,
    s.source_record_id,
    s.company_id,
    c.company_name,
    s.signal_family,
    s.signal_type,
    s.headline,
    s.product_name,
    s.occurred_at,
    s.vendor_confidence,
    s.source_url,
    k.kept_signal_id is not null                                                       as is_corroborated_by_product_feed,
    case when s.signal_family = 'news' and coalesce(c.name_token_is_specific, false)
         then position(c.name_token in replace(lower(s.headline), ' ', '')) = 0
         else false end                                                                as is_entity_mismatch,
    cast(s.occurred_at as date) >  {{ lookback_start() }}
        and cast(s.occurred_at as date) <= {{ as_of_date() }}                           as is_in_lookback,
    r.account_id,
    r.resolution_status,
    r.match_method,
    r.match_confidence,
    coalesce(r.needs_review, false)                                                    as is_match_pending_review
from deduped as s
left join companies  as c on s.company_id = c.company_id
left join resolution as r on s.company_id = r.company_id
left join (select distinct kept_signal_id from launch_duplicates) as k
    on s.signal_id = k.kept_signal_id
