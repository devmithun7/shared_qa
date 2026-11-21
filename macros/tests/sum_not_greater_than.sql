{#
    sum_not_greater_than

    For each group, the sum of the tested column must not be more than a limit.
    The limit is aggregated per group from limit_column, in this model or in
    limit_model. dbt_expectations can only check that totals are equal, or that
    they sit between fixed numbers.

    Group keys are matched null safe (is not distinct from), so null keys
    don't cause false failures. Groups with no limit are not reported; use a
    relationship test for those. tolerance allows small rounding differences.
#}

{% test sum_not_greater_than(
    model,
    column_name,
    group_by,
    limit_column,
    limit_model=None,
    limit_group_by=None,
    limit_aggregate='max',
    row_condition=None,
    limit_row_condition=None,
    tolerance=0
) %}

{% set limit_model = limit_model if limit_model is not none else model %}
{% set limit_group_by = limit_group_by if limit_group_by is not none else group_by %}

{% if group_by is string or limit_group_by is string %}
    {{ exceptions.raise_compiler_error("sum_not_greater_than: group_by and limit_group_by must be lists") }}
{% endif %}
{% if group_by | length == 0 or group_by | length != limit_group_by | length %}
    {{ exceptions.raise_compiler_error("sum_not_greater_than: group_by and limit_group_by must be non empty lists of the same length") }}
{% endif %}
{% if limit_aggregate | lower not in ['max', 'min', 'sum'] %}
    {{ exceptions.raise_compiler_error("sum_not_greater_than: limit_aggregate must be max, min or sum") }}
{% endif %}

with totals as (

    select
        {%- for g in group_by %}
        {{ g }} as group_{{ loop.index }},
        {%- endfor %}
        sum({{ column_name }}) as total
    from {{ model }}
    {%- if row_condition %}
    where {{ row_condition }}
    {%- endif %}
    group by
        {%- for g in group_by %}
        {{ g }}{{ "," if not loop.last }}
        {%- endfor %}

),

limits as (

    select
        {%- for g in limit_group_by %}
        {{ g }} as group_{{ loop.index }},
        {%- endfor %}
        {{ limit_aggregate | lower }}({{ limit_column }}) as limit_value
    from {{ limit_model }}
    {%- if limit_row_condition %}
    where {{ limit_row_condition }}
    {%- endif %}
    group by
        {%- for g in limit_group_by %}
        {{ g }}{{ "," if not loop.last }}
        {%- endfor %}

)

select
    {%- for g in group_by %}
    totals.group_{{ loop.index }},
    {%- endfor %}
    totals.total,
    limits.limit_value
from totals
inner join limits
    on {% for g in group_by -%}
    totals.group_{{ loop.index }} is not distinct from limits.group_{{ loop.index }}{{ " and " if not loop.last }}
    {%- endfor %}
where totals.total > limits.limit_value + {{ tolerance }}

{% endtest %}
