---
name: partitioning-assessment
description: Guide GitHub Copilot to assess whether SQL Server table partitioning is appropriate — and usually recommend simpler fixes first. USE WHEN someone proposes partitioning a large table, asks if partitioning will speed up queries, or wants a partitioning decision with evidence.
---

# Partitioning Assessment

Use this skill when partitioning comes up. Partitioning is primarily a
**manageability** feature (fast switch-in/switch-out, sliding-window retention),
**not** a general query-performance fix. Be skeptical and evidence-driven.

## Guardrail
**Do not recommend partitioning as a default tuning step.** Most slow-query
problems here are solved by a sargable rewrite, a supporting index, or updated
statistics. Establish those first.

## Evidence to gather before any recommendation
1. **Table size** — row count and space (`sys.dm_db_partition_stats`). Partitioning
   rarely pays off below tens of millions of rows.
2. **Date/range access pattern** — do queries filter/scan by a clear range key
   (e.g. `InvoiceDate`)? Partition elimination only helps range-aligned queries.
3. **Retention requirements** — is old data aged out on a schedule? Sliding-window
   purge via partition `SWITCH` is a strong partitioning motivation.
4. **Maintenance windows** — would partition-level index rebuilds / stats help
   operations fit a window?
5. **Sliding-window needs** — recurring load/archive of whole ranges.
6. **Aligned indexes** — would indexes need to be partition-aligned? Assess the
   rebuild cost and impact on existing `IX_Demo_*` indexes.
7. **Operational complexity** — partition functions/schemes, filegroups, aligned
   indexes, and switch automation add real ongoing overhead.

## Recommend simpler fixes first
Sargable predicate → supporting/covering index → updated statistics →
(only with evidence) plan forcing / Query Store hints → **then** consider
partitioning.

## Return a decision
One of:
- **Recommend partitioning** — with the specific evidence (size, range pattern,
  retention/maintenance need) and the partition key/strategy.
- **Do not partition (yet)** — name the simpler fix that addresses the actual
  problem.
- **Needs more evidence** — list exactly what to collect.

Always state the **caveats**: partitioning may not improve (and can regress)
query performance if queries are not range-aligned, and it increases operational
complexity.

## Reference
- `scripts/sql/13-partitioning-assessment-helper.sql` (size, row distribution by
  year and year-month, existing indexes, decision checklist)
