{#- Fails for every row where the expression is false.
    Works at model level or column level (column_name is accepted and ignored). -#}
{% test expression_is_true(model, expression, column_name=none) %}
select *
from {{ model }}
where not ({{ expression }})
{% endtest %}
