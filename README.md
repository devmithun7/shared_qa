# shared_qa

A shared dbt testing package. Every team installs this one package and gets the same data tests at the same versions, then adds the tests it needs to its own models.

## What you get

| Source | What it adds |
|---|---|
| [dbt_expectations](https://github.com/metaplane/dbt-expectations) | The main test library. Use these tests first. |
| [dbt_utils](https://github.com/dbt-labs/dbt-utils) | Used only for checks dbt_expectations doesn't have, such as `relationships_where`, `mutually_exclusive_ranges`, `equality` and `sequential_values`. |
| shared_qa | Four custom tests for checks neither library has. See [Custom tests](#custom-tests). |

Installing shared_qa installs both libraries, so you don't need to list them in your own `packages.yml`.

## Requirements

* dbt 1.10 or later. Test arguments go under `arguments:`.
* The dbt_date time zone variable in your `dbt_project.yml`. Without it, the dbt_expectations recency tests fail to compile.

```yaml
vars:
  "dbt_date:time_zone": "America/New_York"
```

## Install

Add this to your project's `packages.yml`, then run `dbt deps`:

```yaml
packages:
  - git: "https://github.com/devmithun7/shared_qa.git"
    revision: "0.2.0"
```

If your project already lists dbt_expectations or dbt_utils, keep their versions inside the ranges in this repo's `packages.yml`, or `dbt deps` will fail.

## Custom tests

The full catalogue for these tests (purpose, layers, expected result, limitations and configuration guidance) is on the [framework page](https://devmithun7.github.io/shared_qa/#custom-test-catalogue).

None of them report null keys, or keys missing from the other model. Pair them with `dbt_expectations.expect_column_values_to_not_be_null` and `dbt_utils.relationships_where`, so each problem shows up in exactly one test.

### relationships_multi_column

Checks that a combination of columns, such as account and month, exists in another model. `dbt_utils.relationships_where` only takes one column. Add it at model level.

| Argument | Required | Meaning |
|---|---|---|
| `columns` | yes | Key columns in this model, as a list |
| `to` | yes | The other model, for example `ref('fact_rev_model_monthly')` |
| `fields` | yes | Matching columns in the other model, as a list in the same order |
| `from_condition` | no | Filter on this model. Default: all rows |
| `to_condition` | no | Filter on the other model, for example `"is_commercial_fl = 'Y'"`. Default: all rows |

### sum_not_greater_than

For each group, the sum of the tested column must not be more than a limit, such as applied amounts against the payment amount. dbt_expectations can only check that totals are equal, or between fixed numbers. Add it to the column being summed. Group keys are matched null safe.

| Argument | Required | Meaning |
|---|---|---|
| `group_by` | yes | Columns that define a group, as a list |
| `limit_column` | yes | Column holding the limit |
| `limit_model` | no | Model holding the limit. Default: this model |
| `limit_group_by` | no | Group columns in `limit_model`. Default: same as `group_by` |
| `limit_aggregate` | no | How to combine limit rows in a group: `max`, `min` or `sum`. Default `max` |
| `row_condition` | no | Filter on this model |
| `limit_row_condition` | no | Filter on `limit_model` |
| `tolerance` | no | Allowed overshoot for rounding. Default `0` |

### value_in_matched_range

Checks that the row a key points at has a range containing this row's value. Use it for SCD2 versions (the event time falls inside `valid_from` and `valid_to`) and for numeric ranges (a contact count falls inside its rate tier). Add it to the key column. A null bound means that side is open.

| Argument | Required | Meaning |
|---|---|---|
| `to` | yes | The model holding the ranges |
| `field` | yes | The key column in that model |
| `value_column` | yes | Column or expression in this model that must fall inside the range |
| `lower_bound_column` | no | Range start. Default `valid_from` |
| `upper_bound_column` | no | Range end. Default `valid_to` |
| `upper_bound_inclusive` | no | `true` when the end value belongs to the range, as in tiers like 0 to 500. Default `false` |

### hierarchy_reaches_root

For a table where each row points at its parent, checks that no node is part of a loop and every node reaches a top level node within `max_depth` levels. Add it to the node id column. It doesn't use recursive queries, so it runs on Trino. Node ids must be unique.

| Argument | Required | Meaning |
|---|---|---|
| `parent_column` | yes | Column holding the parent id |
| `root_condition` | no | When a node has no parent, for example `"parent_id is null or parent_id = '-1'"`. Default: parent is null |
| `max_depth` | no | Most levels allowed above a node. Set it to the depth cap of any walk built on this table. Default `10` |

## Unit tests

Test transformation logic, such as deduplication, source priority and calculations, with [dbt unit tests](https://docs.getdbt.com/docs/build/unit-tests), not pytest. A unit test gives the model fixed input rows for each source or ref it reads, runs the model's SQL on your warehouse and compares the output with the expected rows. Inputs and expected outputs can be written in YAML or kept as CSV files in `tests/fixtures/`.

Run unit tests only in development and CI. dbt Labs recommends this because their inputs are static, so running them in production uses compute without adding any assurance. Leave them out of production runs with:

```bash
dbt build --exclude-resource-type unit_test
```

## Contracts on Trino

The Trino adapter (dbt-trino 1.11) enforces only the `not_null` constraint. `unique`, `primary_key`, `foreign_key` and `check` constraints are not supported, so uniqueness, referential integrity and value rules must stay as data tests.

[Constraints](https://docs.getdbt.com/reference/resource-properties/constraints) only work on `table` and `incremental` models, never on views or ephemeral models. Contracts on incremental models need `on_schema_change` set to `append_new_columns` or `fail`.

## Adding a test

1. Use a [dbt_expectations](https://github.com/metaplane/dbt-expectations) test if one covers the check.
2. If not, use [dbt_utils](https://github.com/dbt-labs/dbt-utils).
3. Only if neither has it, add a custom test under `macros/tests/`.

## Versions

Library versions are ranges, not exact pins, so they don't clash with versions pinned in your own project:

* dbt_expectations `>=0.10.0, <0.11.0`, tested on 0.10.10
* dbt_utils `>=1.3.0, <2.0.0`, tested on 1.4.1

Releases are git tags. Use a patch release for fixes, a minor release for new tests, and a major release when an existing test changes behaviour.
