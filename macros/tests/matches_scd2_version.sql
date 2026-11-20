{#
    matches_scd2_version

    Fails for each fact row whose dimension key points at a version that was
    not valid when the event happened. Validity is valid_from <= event < valid_to,
    and a null valid_to means the version is still current.

    Neither dbt_expectations nor dbt_utils has this check. Null keys and keys
    missing from the dimension are not reported here.
#}

{% test matches_scd2_version(
    model,
    column_name,
    to,
    field,
    event_column,
    valid_from_column='valid_from',
    valid_to_column='valid_to'
) %}

with facts as (

    select
        {{ column_name }} as dimension_key,
        {{ event_column }} as event_at
    from {{ model }}
    where {{ column_name }} is not null

),

versions as (

    select
        {{ field }} as dimension_key,
        {{ valid_from_column }} as valid_from,
        {{ valid_to_column }} as valid_to
    from {{ to }}

)

select
    facts.dimension_key,
    facts.event_at,
    versions.valid_from,
    versions.valid_to
from facts
inner join versions
    on facts.dimension_key = versions.dimension_key
where facts.event_at < versions.valid_from
   or (
        versions.valid_to is not null
        and facts.event_at >= versions.valid_to
   )

{% endtest %}
