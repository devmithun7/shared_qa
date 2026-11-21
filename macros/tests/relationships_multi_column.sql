{#
    relationships_multi_column

    Fails for each row whose combination of key columns has no matching
    combination in another model. dbt_utils.relationships_where only checks a
    single column.

    columns and fields are lists of the same length, matched in order.
    Rows where any key column is null are skipped; test those with a not null test.
    Failing rows show the key values as key_1, key_2 and so on, in column order.
#}

{% test relationships_multi_column(
    model,
    columns,
    to,
    fields,
    from_condition='1=1',
    to_condition='1=1'
) %}

{% if columns is string or fields is string %}
    {{ exceptions.raise_compiler_error("relationships_multi_column: columns and fields must be lists") }}
{% endif %}
{% if columns | length == 0 or columns | length != fields | length %}
    {{ exceptions.raise_compiler_error("relationships_multi_column: columns and fields must be non empty lists of the same length") }}
{% endif %}

with child as (

    select
        {%- for c in columns %}
        {{ c }} as key_{{ loop.index }}{{ "," if not loop.last }}
        {%- endfor %}
    from {{ model }}
    where ({{ from_condition }})
    {%- for c in columns %}
        and {{ c }} is not null
    {%- endfor %}

),

parent as (

    select distinct
        {%- for f in fields %}
        {{ f }} as key_{{ loop.index }},
        {%- endfor %}
        1 as found
    from {{ to }}
    where ({{ to_condition }})

)

select
    {%- for c in columns %}
    child.key_{{ loop.index }}{{ "," if not loop.last }}
    {%- endfor %}
from child
left join parent
    on {% for c in columns -%}
    child.key_{{ loop.index }} = parent.key_{{ loop.index }}{{ " and " if not loop.last }}
    {%- endfor %}
where parent.found is null

{% endtest %}
