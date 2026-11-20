# shared_qa

A shared dbt testing package. Every team installs this one package and gets the same data tests at the same versions, then adds the tests it needs to its own models.

## What you get

| Source | What it adds |
|---|---|
| [dbt_expectations](https://github.com/metaplane/dbt-expectations) | The main test library. Use these tests first. |
| [dbt_utils](https://github.com/dbt-labs/dbt-utils) | Used only for checks dbt_expectations doesn't have: `relationships_where`, `mutually_exclusive_ranges` and `equality`. |
| shared_qa | One custom test, `matches_scd2_version`, for a check neither library has. |

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

## matches_scd2_version

Checks that a fact row's dimension key points at the version of an SCD2 dimension that was valid when the event happened. A fact that joins to the current row instead of the historical one passes a normal relationship test, because the key exists. This test catches it.

A version is valid when `valid_from <= event < valid_to`. A null `valid_to` means the version is still current.

Add it to the fact's dimension key column.

| Argument | Required | Meaning |
|---|---|---|
| `to` | yes | The dimension, for example `ref('dim_customer')` |
| `field` | yes | The key column in the dimension |
| `event_column` | yes | The column or expression holding the event time in the fact |
| `valid_from_column` | no | Version start column in the dimension. Default `valid_from` |
| `valid_to_column` | no | Version end column in the dimension. Default `valid_to` |

It skips null keys and keys missing from the dimension, so use it together with:

* `dbt_expectations.expect_column_values_to_not_be_null` for null keys
* `dbt_utils.relationships_where` for keys that don't exist

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
