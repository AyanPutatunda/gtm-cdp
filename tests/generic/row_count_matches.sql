{#- Fails when the model has a different number of rows than compare_model.
    Used to prove "nothing was silently dropped". -#}
{% test row_count_matches(model, compare_model) %}
with a as (select count(*) as n from {{ model }}),
     b as (select count(*) as n from {{ compare_model }})
select a.n as model_rows, b.n as compare_rows
from a cross join b
where a.n <> b.n
{% endtest %}
