# SSMS Copilot demo prompt sheet

A one-page cheat sheet to drive the live demo. It sequences the exact prompts from
[ask-mode-prompts.md](ask-mode-prompts.md) and [agent-mode-prompts.md](agent-mode-prompts.md)
against the steps in the README. Keep this open on a second monitor.

## Place in the story

- **Stage:** learn and test the complete Ask-to-Agent sequence in SSMS.
- **Enter from:** the README
  [baseline and regression evidence](../README.md#capture-baseline-and-regression-evidence),
  after both Query Store windows exist.
- **This document owns:** the shortest prompt-and-action sequence. The Ask and
  Agent guides remain the explanatory sources.
- **Continue with:** the README
  [guardrail model](../README.md#guardrails-and-execution-identity), then the
  [reviewed-fix validation flow](../README.md#apply-the-reviewed-fix-and-validate).

## Before you start
- Connected in SSMS to **WideWorldImporters** on the SQL Server VM.
- The demo constitution is body-only, so Copilot uses the account connected in
  SSMS. The separate `GHCP_DB_User` test illustrates least-privilege enforcement;
  see [database instructions and execution context](database-instructions.md).
- Baseline and regressed workloads already run, so Query Store has data.

---

## Step 1 — Ask mode: explain the slow procedure
Open `Demo.usp_GetRegionalSalesByYear_Regressed`, then:
```
Explain what this stored procedure does and identify possible performance concerns.
```
```
Rewrite this query to be more sargable without changing the business logic.
```
Expected: Copilot flags `YEAR(InvoiceDate) = @Year` as non-sargable and proposes a
half-open date range (matching the `_Fixed` proc).

## Step 2 — Ask mode: read the plan
Turn on Actual Execution Plan (Ctrl+M), run one regressed call, select the plan, then:
```
Based on this execution plan, explain the likely bottleneck in simple DBA terms.
```
Expected: a Clustered Index/Table Scan over ~10M rows is the bottleneck.

## Step 3 — Agent mode: investigate (read-only)
```
In the WideWorldImporters database on this server, investigate why query performance regressed after the latest workload run. Use Query Store where possible. Do not make any schema or data changes. Return findings as a DBA review table.
```
Review each proposed statement and select **Allow once** only for read-only Query
Store steps.

## Step 4 — Agent mode: quantify the regression
```
Compare the baseline and regressed workload windows in Query Store. Identify the top queries with increased duration, CPU, and logical reads. Include query_id, plan_id, likely cause, and recommended next action.
```
Pair the separate `_Baseline` and `_Regressed` procedures by logical family and
report each phase's `query_id` and `plan_id`. Cross-check against
`scripts/sql/09-query-store-regression-report.sql`.

## Step 5 — Agent mode: options, then a plan
```
Analyze the worst regressed query. Consider query rewrite, indexing, statistics, plan forcing, Query Store hints, and partitioning. Do not implement anything yet.
```
```
Create a remediation plan with risk, expected benefit, validation steps, and rollback steps.
```

## Step 6 — Agent mode: review-only fix script
```
Generate the T-SQL I should review to apply the safest fix in a test environment. Do not execute it automatically.
```
Then **you** apply the fix manually via `scripts/sql/10-apply-fix-options.sql`.

## Step 7 — Agent mode: responsible partitioning
```
Assess whether partitioning is justified for this workload. Use evidence from row counts, date distribution, access pattern, and maintenance needs.
```
Expected: it recommends the rewrite + index first, not partitioning.

---

## Closing line
"Query Store proved the regression and the fix. Copilot accelerated the
investigation, but the DBA — and SQL permissions — stayed in control the whole
time. This is exactly how it works against on-prem SQL Server 2019/2022."
