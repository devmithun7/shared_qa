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
| **Test catalogue** | Document each test’s purpose, parameters, applicable layers, expected result and limitations. |
| **Configuration guidance** | Explain how to configure models, columns, keys, comparison filters, time windows, tolerances and severity. |
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
