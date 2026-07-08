---
name: query-store-regression-review
description: Guide GitHub Copilot Agent Mode to analyze a SQL Server Query Store performance regression safely and read-only. USE WHEN investigating why queries got slower, comparing baseline vs regressed workload windows, or producing a DBA regression review for WideWorldImporters / the Demo schema.
---

# Query Store Regression Review

Use this skill when asked to investigate a performance regression in SQL Server
using Query Store. Work like a careful senior DBA. **Do not make changes** —
investigation is read-only unless the human explicitly approves a specific action.

## Inputs you should establish first
- The database (this demo: `WideWorldImporters`).
- The **workload time windows** to compare. Read them from `Demo.WorkloadLog`
  (`RunLabel` of `baseline`, `regressed`, `fixed`; `StartedAt`/`EndedAt` in UTC).

## Steps
1. **Identify the workload windows** (baseline vs regression) from
   `Demo.WorkloadLog`.
2. **Compare baseline vs regression** for the same queries using:
   `sys.query_store_query`, `sys.query_store_query_text`, `sys.query_store_plan`,
   `sys.query_store_runtime_stats`, `sys.query_store_runtime_stats_interval`.
3. For each query, compare **average duration, CPU time, logical reads, execution
   count, and plan count**.
4. Report **query_id, plan_id, and query text**.
5. Determine **whether the plan changed** (different `plan_id`, seek → scan).
6. **Do not make changes** to data or schema without explicit approval.
7. Return a **DBA review table** (one row per regressed query) with columns:
   `query_id | plan_id | object | baseline_ms | regressed_ms | duration_x |
   reads_x | cpu_x | plan_changed | likely_cause | recommended_action | risk |
   validation | rollback`.
8. Always include **validation and rollback** for any recommendation.
9. **Prefer test/dev validation before production.**
10. **Avoid production write/schema changes unless explicitly requested.**

## Reference queries
The repo's ready-made reports mirror this analysis — use them to cross-check:
- `scripts/sql/08-query-store-baseline-report.sql`
- `scripts/sql/09-query-store-regression-report.sql`
- `scripts/sql/12-query-store-after-fix-report.sql`
- `scripts/sql/14-show-query-store-plan-details.sql`

## Likely causes to check (in order)
1. Non-sargable predicate (e.g. `YEAR(InvoiceDate) = @Year`).
2. Missing or dropped supporting index.
3. Stale statistics / bad cardinality estimates.
4. Plan change (parameter sensitivity, recompile).

Recommend the **simplest safe fix first** (sargable rewrite + index), and only
then consider plan forcing, Query Store hints, or partitioning.
