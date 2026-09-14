{#
  The only macros in this project, and each exists for one reason:
  DuckDB (local) and Snowflake (production) spell the same thing differently.
  Everything else — normalisation, matching, scoring — is plain SQL you can
  read in the models.
#}

{# ---- JSON stored as text -> a string value ------------------------------ #}
{% macro json_get(column, key) -%}
    {{ return(adapter.dispatch('json_get', 'gtm_cdp')(column, key)) }}
{%- endmacro %}

{% macro default__json_get(column, key) -%}
    json_extract_string({{ column }}, '$.{{ key }}')
{%- endmacro %}

{% macro snowflake__json_get(column, key) -%}
    try_parse_json({{ column }}):"{{ key }}"::varchar
{%- endmacro %}


{# ---- Distinct, sorted, comma-separated list ------------------------------ #}
{% macro agg_list(expr, separator=', ') -%}
    {{ return(adapter.dispatch('agg_list', 'gtm_cdp')(expr, separator)) }}
{%- endmacro %}

{% macro default__agg_list(expr, separator) -%}
    string_agg(distinct {{ expr }}, '{{ separator }}' order by {{ expr }})
{%- endmacro %}

{% macro snowflake__agg_list(expr, separator) -%}
    nullif(listagg(distinct {{ expr }}, '{{ separator }}') within group (order by {{ expr }}), '')
{%- endmacro %}


{# ---- A seed column whose name is a SQL keyword ("timestamp") -------------
   Snowflake upper-cases unquoted seed columns; DuckDB keeps them as written. #}
{% macro keyword_column(name) -%}
    {{ return(adapter.dispatch('keyword_column', 'gtm_cdp')(name)) }}
{%- endmacro %}

{% macro default__keyword_column(name) -%}
    "{{ name }}"
{%- endmacro %}

{% macro snowflake__keyword_column(name) -%}
    "{{ name | upper }}"
{%- endmacro %}


{# ---- The as-of date, in one place ----------------------------------------
   The seeds are a frozen snapshot, so every window is measured from
   var('as_of_date'). Pass 'today' to use the warehouse's current date. #}
{% macro as_of_date() -%}
    {%- if var("as_of_date") | string | lower in ('today', 'current_date') -%}
        current_date
    {%- else -%}
        cast('{{ var("as_of_date") }}' as date)
    {%- endif -%}
{%- endmacro %}

{% macro lookback_start() -%}
    {{ dbt.dateadd('day', -1 * var('lookback_days') | int, as_of_date()) }}
{%- endmacro %}


{# ---- Distinct, sorted list (as above) but ordered by a DIFFERENT expression -
   Used where the reading order matters and is not alphabetical, e.g.
   account_360.action_reasons must lead with the strongest signal.
   DISTINCT is dropped on purpose: Snowflake's LISTAGG only allows a custom
   WITHIN GROUP (ORDER BY ...) when DISTINCT is absent, and the inputs here
   are already unique (one row per signal_id). #}
{% macro agg_list_ordered(expr, order_by, separator=', ') -%}
    {{ return(adapter.dispatch('agg_list_ordered', 'gtm_cdp')(expr, order_by, separator)) }}
{%- endmacro %}

{% macro default__agg_list_ordered(expr, order_by, separator) -%}
    string_agg({{ expr }}, '{{ separator }}' order by {{ order_by }})
{%- endmacro %}

{% macro snowflake__agg_list_ordered(expr, order_by, separator) -%}
    nullif(listagg({{ expr }}, '{{ separator }}') within group (order by {{ order_by }}), '')
{%- endmacro %}
