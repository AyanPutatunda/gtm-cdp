{#
  Schemas are named after the layer: raw / cleansed / unified.

  - Local DuckDB and a target named 'prod' use the layer name exactly, so
    the warehouse reads like the project.
  - Any other target (dev, ci, a personal Snowflake target) is prefixed with
    its own schema, e.g. DEV_RAW / DEV_CLEANSED / DEV_UNIFIED, so a dev run
    can never overwrite production tables.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema | trim }}
    {%- elif target.type == 'duckdb' or target.name == 'prod' -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ target.schema | trim }}_{{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
