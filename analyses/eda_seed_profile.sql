/*
  EDA · Column profile of every raw seed
  One row per column: rows, populated, blank, distinct, and whether the column
  is unique across the table (a candidate key).

    dbt compile -s eda_seed_profile     # then run target/compiled/.../eda_seed_profile.sql

  This is the first thing I ran, before writing a model. It stays in the
  project so the profile can be re-run whenever the seeds change.

  The seed list is spelled out rather than read from the graph, because dbt
  infers dependencies at parse time, when the graph isn't populated yet.
*/
{%- set seeds = [
    'raw_account_org_map', 'raw_api_keys', 'raw_cli_wizard', 'raw_datasets',
    'raw_docs_mcp_events', 'raw_experiments', 'raw_members', 'raw_news_events',
    'raw_organizations', 'raw_products', 'raw_projects', 'raw_prompts',
    'raw_salesforce_accounts', 'raw_segment_pages', 'raw_signal_companies',
    'raw_tech_detections', 'raw_trace_volume', 'raw_users'
] -%}

{%- for seed_name in seeds %}
    {%- set relation = ref(seed_name) -%}
    {%- set columns = adapter.get_columns_in_relation(relation) if execute else [] %}
    {%- for column in columns %}
        {%- set quoted = adapter.quote(column.name) %}
select
    '{{ seed_name }}'                                                   as table_name,
    '{{ column.name }}'                                                 as column_name,
    '{{ column.dtype }}'                                                as data_type,
    count(*)                                                            as rows_total,
    count({{ quoted }})                                                 as rows_populated,
    sum(case when nullif(trim(cast({{ quoted }} as varchar)), '') is null
             then 1 else 0 end)                                         as rows_null_or_blank,
    count(distinct {{ quoted }})                                        as distinct_values,
    count(distinct {{ quoted }}) = count(*) and count(*) > 1            as is_unique_key
from {{ relation }}
        {%- if not loop.last %}
union all
        {%- endif %}
    {%- endfor %}
    {%- if not loop.last %}
union all
    {%- endif %}
{%- endfor %}

order by table_name, column_name
