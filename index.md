---
layout: default
title: Unified dbt Testing Framework
---

## Objective

Establish a shared testing framework for **Finance, CM360, Marketing, Sales and other data domains**. Teams will select and configure applicable checks from a centrally maintained catalogue, using consistent standards for validation, execution and reporting.

The framework will provide a **versioned dbt package, documented test catalogue and configuration guidance**, allowing reusable tests to be adopted across projects.

## What the framework will provide

| Component | Purpose |
|---|---|
| **Reusable test package** | Use **`dbt_utils` and `dbt_expectations` as the primary libraries for reusable data tests**. When an applicable test is unavailable in either package, implement a custom test. Reusable custom checks will be included in the shared package. |
| **Test catalogue** | Document each **custom** test’s purpose, parameters, applicable layers, expected result and limitations. Tests from `dbt_expectations` and `dbt_utils` are documented by those libraries. See the [custom test catalogue](#custom-test-catalogue). |
| **Configuration guidance** | Explain how to configure each **custom** test: models, columns, keys, comparison filters, time windows, tolerances and severity. |
| **Execution and reporting standards** | Define when checks run, how failures are reported and how execution history is retained. |

Choose one implementation when multiple packages offer equivalent checks for the same requirement.

## Testing responsibilities by layer

Each layer should validate the rules it introduces and the risks created by its processing. **Grain (what one row represents) must be defined before choosing uniqueness or row-count checks.**

### 1. Source / landing: validate the data available for transformation

This layer covers the raw tables that dbt reads after ingestion from the original systems.

**Testing focus**

- **Freshness:** Check data recency against the agreed delivery SLA.
- **Required fields and source keys:** Validate essential fields and source-key integrity according to the source’s declared grain.
- **Structure:** Check that required input columns are available and have the expected data types.

Source-key checks should reflect the source’s structure. Sources that retain change history may legitimately contain multiple records for the same business key.

Freshness is configured and evaluated through [dbt source freshness](https://docs.getdbt.com/reference/resource-configs/freshness).

### 2. Intermediate: validate transformation logic

Intermediate models prepare data by applying business rules, combining sources and producing the required structure.

**Testing focus**

- **Filtering:** Retain the eligible population and apply intended exclusions.
- **Deduplication and source priority:** Select the correct surviving record when duplicates or competing sources exist.
- **Calculations and conversions:** Validate derived fields, mappings, formulas and conversions.
- **Joins and grain:** Detect unexpected row multiplication, record loss or changes to what one row represents.
- **Business logic and edge cases:** Use **[dbt unit tests](https://docs.getdbt.com/docs/build/unit-tests) during development and CI** to validate intermediate transformations with controlled inputs and expected outputs.

A dbt unit test gives the model fixed input rows for each source or ref it reads, runs the model's SQL on the warehouse and compares the actual output with the expected rows. Inputs and expected outputs can be written in YAML or kept as CSV files in `tests/fixtures/`, and they only need the columns the rule uses. Expected behaviour should be defined by the business rules, including applicable edge cases.

Run unit tests only in development and CI. dbt Labs recommends this because their inputs are static, so running them in production uses compute without adding any assurance. Exclude them from production runs with `dbt build --exclude-resource-type unit_test`.

Reconcile the model’s output against the **eligible input population after applying the intended rules**. Raw and intermediate row counts may legitimately differ because of filtering, deduplication or other transformations.

### 3. Dimensions: validate entity identity and history

Dimensions describe business entities and their attributes.

**Testing focus**

- **Surrogate keys:** Validate that each dimension row has a unique, non-null surrogate key.
- **Business identity:** Validate business-key uniqueness at the intended grain.
- **Required attributes:** Check that mandatory attributes are populated and valid. Optional attributes may remain null.
- **Relationships:** Validate applicable links to other dimensions.
- **SCD2 history, where used:** Validate version uniqueness, the agreed current-record policy, non-overlapping business-effective periods and correct history changes.

For SCD2 dimensions, business keys may repeat across historical versions. Each version must remain identifiable, and current-record checks must account for the model’s deletion or deactivation policy.

### 4. Facts: validate business activity and dimension links

Facts represent business transactions, events or snapshots.

**Testing focus**

- **Grain and required keys:** Validate the intended transaction, event or snapshot identity.
- **Referential integrity:** Check selected relationships to dimensions according to business impact and the agreed exception policy.
- **Coverage and reconciliation:** Compare eligible record IDs, counts and business totals with the upstream population.
- **Measures and dates:** Validate new calculations, date alignment and historical dimension mapping.
- **Join behaviour:** Detect duplicated facts, missing eligible records or incorrect dimension assignments.

When joining to an SCD2 dimension, confirm that the selected dimension version is valid for the fact’s relevant business date. Referential integrity alone does not establish that the correct historical version was selected.

### 5. Aggregates: validate reporting calculations

Aggregates summarize detailed records into reporting groups.

**Testing focus**

- **Reporting grain:** Validate one row per intended combination of reporting keys.
- **Reconciliation:** Compare grouped counts and business totals with the contributing detail records.
- **Metric definitions:** Validate sums, distinct counts, ratios, averages and other calculations.
- **Coverage:** Detect missing expected groups or periods and double counting.

Reconciliation should use consistent filters, periods and business groups. Validate results at the reporting-group level because matching overall totals can conceal incorrect allocation between groups.

## Shared validation standards

### Reconcile equivalent populations

For intermediate, fact and aggregate models, comparisons must use consistent eligibility rules, time windows, business groups and currencies. Account for filtering, deduplication and aggregation before evaluating differences.

**Equal row counts alone are insufficient.** Use matching-key coverage and business totals where needed to validate that the correct records and values are preserved.

### Define relationship policies

For each relationship, document:

- Whether the key is mandatory or may be null.
- Whether an approved unknown member is permitted.
- How late-arriving dimension records are handled, **if applicable**.
- Whether historical, date-effective matching is required.

dbt’s `relationships` test excludes null values. A mandatory foreign key therefore also needs a separate `not_null` check. See [dbt data tests](https://docs.getdbt.com/reference/resource-properties/data-tests).

## Implementation and execution

| Area | Approach |
|---|---|
| **Test implementation** | Select applicable checks from `dbt_utils` and `dbt_expectations`. Develop custom tests for requirements those packages do not support. Document the parameters and expected behaviour of each catalogue entry. |
| **Development and CI** | Run **dbt unit tests for intermediate business logic and edge cases** in development and CI, and exclude them from production runs. Run relevant dbt data tests on changed models and affected dependencies. Check documentation and published schemas. |
| **Production** | Run selected data tests with model builds. Explicitly schedule source freshness checks and downstream reconciliation according to business criticality and execution cost. |
| **Incremental processing** | For incremental models, validate inserts, updates, reruns and backfills through controlled scenarios. Include delete handling and late-arriving data where applicable. Check the resulting persisted target state. |
| **Reporting and response** | Retain execution history, failure details and actionable evidence. Apply the configured warning or error policy. |

## Avoiding duplicate testing

Assign each business rule a **primary testing layer**, normally where its logic is introduced.

- Validate transformation logic where the transformation occurs.
- Repeat checks downstream when new joins, calculations, changes to grain or persisted data introduce an additional risk.
- Avoid repeating equivalent checks on attributes carried forward unchanged.
- Validate downstream record preservation and reconciliation where needed, without repeating the original calculation test.

This approach follows dbt’s guidance to focus testing on new transformations and risks while avoiding equivalent checks on unchanged attributes. See [dbt guidance on test placement](https://docs.getdbt.com/blog/test-smarter-where-tests-should-go).

## Custom test catalogue

These are the framework's own tests, for checks that neither dbt_expectations nor dbt_utils covers. Tests from those two libraries are documented by the libraries themselves. The tests live in the [shared_qa package](https://github.com/devmithun7/shared_qa).

None of the custom tests report null keys, or keys missing from the other model. Pair each one with `dbt_expectations.expect_column_values_to_not_be_null` and `dbt_utils.relationships_where`, so every problem shows up in exactly one test.

Each test was checked on dbt 1.10 and 1.11: it passes on correct data and catches planted defects, with the exact number of failing rows expected. All four compile to valid Trino SQL.

### relationships_multi_column

**Purpose:** checks that a combination of columns, such as account and month, exists in another model. `dbt_utils.relationships_where` only checks one column.

| Parameter | Required | Meaning |
|---|---|---|
| `columns` | yes | Key columns in the tested model, as a list |
| `to` | yes | The other model |
| `fields` | yes | Matching columns in the other model, as a list in the same order |
| `from_condition` | no | Filter on the tested model. Default: all rows |
| `to_condition` | no | Filter on the other model. Default: all rows |

**Applicable layers:** facts and aggregates that link to another model on more than one column.

**Expected result:** passes when every key combination in the tested model has a match. Each failing row shows the unmatched key values as `key_1`, `key_2` and so on, in column order.

**Limitations:** rows where any key column is null are skipped. The column and field lists must be the same length, or the test fails to compile.

**Configuration:** add it at model level. Use `to_condition` when the match has to land on a specific kind of row.

```yaml
models:
  - name: fact_commercial_monthly
    data_tests:
      - shared_qa.relationships_multi_column:
          arguments:
            columns: [account_id, revenue_month]
            to: ref('fact_revenue_monthly')
            fields: [account_id, revenue_month]
            to_condition: "is_commercial_fl = 'Y'"
          config:
            tags: [baseline]
```

### sum_not_greater_than

**Purpose:** for each group, checks that the sum of a column is not more than a limit, such as the amounts applied to invoices against the payment amount. dbt_expectations can only check that totals are equal, or that they sit between fixed numbers.

| Parameter | Required | Meaning |
|---|---|---|
| `group_by` | yes | Columns that define a group, as a list |
| `limit_column` | yes | Column holding the limit |
| `limit_model` | no | Model holding the limit. Default: the tested model |
| `limit_group_by` | no | Group columns in `limit_model`. Default: same as `group_by` |
| `limit_aggregate` | no | How limit rows in a group are combined: `max`, `min` or `sum`. Default `max` |
| `row_condition` | no | Filter on the tested model |
| `limit_row_condition` | no | Filter on `limit_model` |
| `tolerance` | no | Allowed overshoot for rounding. Default `0` |

**Applicable layers:** facts, and aggregates built from them.

**Expected result:** passes when no group's total is more than its limit plus the tolerance. Each failing row shows the group keys, the total and the limit.

**Limitations:** groups that have no limit row are not reported. Group keys are matched null safe, so a null key is compared like any other value instead of failing by mistake.

**Configuration:** add it to the column being summed. When the limit is repeated on every row, as with a payment amount on each payment and invoice row, keep the default `max`. When the limit is spread over several rows, use `sum`. Use a small tolerance for amounts that are split and rounded.

```yaml
models:
  - name: fact_payment
    columns:
      - name: applied_amount
        data_tests:
          - shared_qa.sum_not_greater_than:
              arguments:
                group_by: [payment_id]
                limit_column: payment_amount
                tolerance: 0.01
              config:
                tags: [reconciliation]
                severity: warn
```

### value_in_matched_range

**Purpose:** checks that the row a key points at has a range that contains this row's value. For SCD2 dimensions, it proves a fact picked the version that was valid at the time of the event. A normal relationship test misses this, because the wrong version's key still exists. For numeric ranges, it proves a value sits inside its matched range, such as a contact count inside its rate tier.

| Parameter | Required | Meaning |
|---|---|---|
| `to` | yes | The model holding the ranges |
| `field` | yes | The key column in that model |
| `value_column` | yes | Column or expression in the tested model that must fall inside the range |
| `lower_bound_column` | no | Range start. Default `valid_from` |
| `upper_bound_column` | no | Range end. Default `valid_to` |
| `upper_bound_inclusive` | no | `true` when the end value belongs to the range. Default `false` |

**Applicable layers:** facts that join to an SCD2 dimension, and any model that looks a value up in a table of ranges, such as rate tiers or discount windows.

**Expected result:** passes when every value falls inside its matched range. The range is `start <= value < end`, or `start <= value <= end` with `upper_bound_inclusive: true`. Each failing row shows the key, the value and the range it should have fallen into.

**Limitations:** null keys and null values are skipped. A null bound means that side of the range is open, so a null `valid_to` means the version is still current.

**Configuration:** add it to the key column. SCD2 versions usually end exactly when the next one starts, so keep the default exclusive end. Tiers written as 0 to 500 and 501 to 2,500 include their end value, so set `upper_bound_inclusive: true`. If the two sides store time with different types, pass an expression such as `"cast(invoice_month as timestamp)"` as `value_column`.

```yaml
models:
  - name: fact_invoice_line
    columns:
      - name: customer_sk
        data_tests:
          - shared_qa.value_in_matched_range:
              arguments:
                to: ref('dim_customer')
                field: customer_sk
                value_column: invoice_at
              config:
                tags: [scd2]
      - name: rate_tier_sk
        data_tests:
          - shared_qa.value_in_matched_range:
              arguments:
                to: ref('dim_rate_tier')
                field: rate_tier_sk
                value_column: contact_count
                lower_bound_column: min_contacts
                upper_bound_column: max_contacts
                upper_bound_inclusive: true
```

### hierarchy_reaches_root

**Purpose:** for a table where each row points at its parent, checks that no node is part of a loop, and that every node reaches a top level node within a set number of levels. Neither library can walk a hierarchy.

| Parameter | Required | Meaning |
|---|---|---|
| `parent_column` | yes | Column holding the parent id |
| `root_condition` | no | When a node has no parent. Default: the parent is null |
| `max_depth` | no | Most levels allowed above a node. Default `10` |

**Applicable layers:** dimensions and intermediate models that hold a parent and child structure, such as a partner hierarchy.

**Expected result:** passes when every node reaches the top within `max_depth` levels. Each failing row shows the node and the problem: `part of a loop`, or `no top level node within N levels`. A node sitting under a loop gets the second message.

**Limitations:** node ids must be unique, so add a uniqueness test. A parent that doesn't exist as a node counts as reaching the top, so check parents with a relationship test. The walk is written as one join per level instead of a recursive query, so it runs on Trino, but a very large `max_depth` means a longer query.

**Configuration:** add it to the node id column. Use `root_condition` when top level nodes carry a placeholder parent such as `'-1'`. Set `max_depth` to the depth cap of any hierarchy walk built on this table. The test then fails when the walk would cut a branch short.

```yaml
models:
  - name: dim_partner
    columns:
      - name: partner_id
        data_tests:
          - shared_qa.hierarchy_reaches_root:
              arguments:
                parent_column: parent_partner_id
                root_condition: "parent_partner_id is null or parent_partner_id = '-1'"
                max_depth: 4
              config:
                tags: [baseline]
```

## Recommendations to consider

The following capabilities could strengthen **schema consistency, development standards and project-wide quality checks** alongside the shared testing framework.

| Recommendation | What it is | How it could be used |
|---|---|---|
| **[dbt model contracts](https://docs.getdbt.com/docs/mesh/govern/model-contracts)** | A built-in dbt feature that verifies a model’s output column names and data types against its declared schema. Additional constraints can be specified where supported. On Trino, the only constraint enforced is `not_null`. | Consider contracts for stable, shared dimensions, facts and aggregates. Declare every output column and its data type in YAML and enable contract enforcement. During model builds, dbt will detect a mismatch between the declared schema and the model output, helping prevent unintended schema changes from reaching downstream consumers. Keep uniqueness, primary key, foreign key and value checks as data tests. |
| **[dbt-checkpoint](https://github.com/dbt-checkpoint/dbt-checkpoint)** | A collection of configurable pre-commit hooks for checking dbt project conventions and metadata, including documentation, naming, required test declarations and contract configuration. | Run selected hooks locally before commits and in pull-request CI. Generate the artifacts required by those hooks and use agreed checks as merge requirements. This provides early feedback when changes do not meet the project’s development standards. |
| **[dbt-project-evaluator](https://dbt-labs.github.io/dbt-project-evaluator/)** | A dbt Labs package that reviews project metadata and model dependencies against configurable best practices for modeling, testing, documentation, structure, materializations and governance. | Use it in CI and periodic project reviews to identify test-coverage gaps, missing documentation and dependency patterns that conflict with agreed layer standards. Configure applicable rules and exceptions, initially report findings as warnings, and consider enforcing selected requirements as CI failures. |

### Considerations for adoption

- **Contract support on Trino:** The Trino adapter (dbt-trino 1.11) enforces only `not_null`. `unique`, `primary_key`, `foreign_key` and `check` constraints are not supported, so uniqueness, referential integrity and value rules must stay as data tests. [Constraints](https://docs.getdbt.com/reference/resource-properties/constraints) only work on `table` and `incremental` models, never on views or ephemeral models, and contracts on incremental models need `on_schema_change` set to `append_new_columns` or `fail`.
- **Coverage versus results:** Metadata checks can establish that tests and freshness configurations are declared. Their execution results must still come from running the relevant data tests, freshness checks and transformation tests.
- **Version compatibility:** Select compatible versions before adoption. Project Evaluator 2.x requires dbt 2.0 or later and runs checks locally over project metadata; projects using dbt 1.x should use the compatible 1.x package.
- **Overlapping checks:** Configure dbt-checkpoint and Project Evaluator so equivalent documentation and test-declaration rules have a clear primary enforcement point.
