{#
    hierarchy_reaches_root

    For a table where each row points at its parent, fails for each node that
    is part of a loop, or that doesn't reach a top level node within max_depth
    levels. Neither library can walk a hierarchy.

    root_condition says when a node has no parent. It defaults to the parent
    column being null; use it for placeholder values such as '-1'.
    max_depth is the most levels allowed above a node. Set it to the depth cap
    of any hierarchy walk built on this table, so the test fails when the walk
    would cut a branch short.

    The walk is unrolled into max_depth + 1 joins, so it runs on any warehouse,
    including Trino, without recursive queries.
    Node ids must be unique. A parent that doesn't exist as a node counts as
    reaching the top; test that with a relationship test.
#}

{% test hierarchy_reaches_root(
    model,
    column_name,
    parent_column,
    root_condition=None,
    max_depth=10
) %}

{% set root_condition = root_condition if root_condition else parent_column ~ " is null" %}
{% if max_depth is not number or max_depth < 1 %}
    {{ exceptions.raise_compiler_error("hierarchy_reaches_root: max_depth must be a whole number of 1 or more") }}
{% endif %}
{% set steps = max_depth | int + 1 %}

with nodes as (

    select
        {{ column_name }} as node_id,
        case when {{ root_condition }} then null else {{ parent_column }} end as parent_id
    from {{ model }}
    where {{ column_name }} is not null

),

step_1 as (

    select
        node_id as start_id,
        parent_id as ancestor_id,
        0 as loop_found
    from nodes

),

{%- for i in range(2, steps + 1) %}

step_{{ i }} as (

    select
        previous.start_id,
        nodes.parent_id as ancestor_id,
        case
            when previous.loop_found = 1 or previous.ancestor_id = previous.start_id then 1
            else 0
        end as loop_found
    from step_{{ i - 1 }} as previous
    left join nodes
        on nodes.node_id = previous.ancestor_id

),

{%- endfor %}

final as (

    select
        start_id,
        ancestor_id,
        case
            when loop_found = 1 or ancestor_id = start_id then 1
            else 0
        end as loop_found
    from step_{{ steps }}

)

select
    start_id as node_id,
    case
        when loop_found = 1 then 'part of a loop'
        else 'no top level node within {{ max_depth }} levels'
    end as problem
from final
where loop_found = 1
   or ancestor_id is not null

{% endtest %}
