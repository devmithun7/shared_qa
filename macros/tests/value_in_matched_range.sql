{#
    value_in_matched_range

    Fails for each row whose key points at a row in another model whose range
    does not contain the row's value. Works for dates (the SCD2 version valid at
    the time of an event) and numbers (the rate tier whose range holds a
    contact count).

    The range is lower_bound <= value < upper_bound, or
    lower_bound <= value <= upper_bound when upper_bound_inclusive is true.
    A null bound means that side is open, so a null valid_to means still current.

    Not reported here, on purpose: null keys, null values, and keys missing
    from the other model. Test those with not null and relationship tests.
#}

{% test value_in_matched_range(
    model,
    column_name,
    to,
    field,
    value_column,
    lower_bound_column='valid_from',
    upper_bound_column='valid_to',
    upper_bound_inclusive=false
) %}

with rows_to_check as (

    select
        {{ column_name }} as match_key,
        {{ value_column }} as checked_value
    from {{ model }}
    where {{ column_name }} is not null
      and {{ value_column }} is not null

),

ranges as (

    select
        {{ field }} as match_key,
        {{ lower_bound_column }} as lower_bound,
        {{ upper_bound_column }} as upper_bound
    from {{ to }}

)

select
    rows_to_check.match_key,
    rows_to_check.checked_value,
    ranges.lower_bound,
    ranges.upper_bound
from rows_to_check
inner join ranges
    on rows_to_check.match_key = ranges.match_key
where (
        ranges.lower_bound is not null
        and rows_to_check.checked_value < ranges.lower_bound
   )
   or (
        ranges.upper_bound is not null
        and rows_to_check.checked_value {{ ">" if upper_bound_inclusive else ">=" }} ranges.upper_bound
   )

{% endtest %}
