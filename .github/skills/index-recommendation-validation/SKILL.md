---
name: index-recommendation-validation
description: Guide GitHub Copilot to validate a proposed SQL Server index before recommending it — checking existing indexes, duplication/overlap, write and storage overhead, and query frequency. USE WHEN considering CREATE INDEX, evaluating a missing-index DMV suggestion, or deciding whether an index is the right fix for a slow query.
---

# Index Recommendation Validation

Use this skill before recommending any index. An index is a trade-off, not a free
win. Validate it like a senior DBA and return a clear verdict.

## Steps
1. **Check existing indexes first** on the target table
   (`sys.indexes`, `sys.index_columns`) before proposing a new one.
2. **Avoid duplicate or overlapping indexes.** If an existing index already covers
   the predicate (or could by adding INCLUDE columns), prefer modifying it.
3. **Estimate write overhead** — every nonclustered index adds cost to
   INSERT/UPDATE/DELETE. Consider how write-heavy the table is.
4. **Consider storage** — estimate size from row count, key width, and INCLUDE
   columns; wide INCLUDE lists on large tables are expensive.
5. **Consider query frequency** — use Query Store execution counts. A rare query
   rarely justifies a new permanent index.
6. **Treat missing-index DMV output as a suggestion, not truth**
   (`sys.dm_db_missing_index_*`). It ignores existing indexes, write cost, and
   overlap, and tends to over-recommend wide covering indexes.
7. **Consider a query rewrite or a statistics update first.** A non-sargable
   predicate (e.g. `YEAR(col) = @y`) often can't use any index — fix the query
   before adding an index.
8. **Return exactly one verdict:**
   - **Create** — new index is justified (state the exact DDL, key + INCLUDE,
     compression, and expected benefit).
   - **Modify** — extend/replace an existing index instead.
   - **Reject** — not worth it (duplicate/overlap, low frequency, rewrite is
     better).
   - **Needs more evidence** — state what to gather (frequency, selectivity,
     write ratio, before/after Query Store metrics).

## Always include
- **When** to apply, the **risk**, how to **validate** (compare Query Store
  duration/reads before vs after), and how to **roll back** (`DROP INDEX`).
- Keep demo indexes under the `IX_Demo_` prefix and the `Demo` schema.

## Reference
- `scripts/sql/04-create-baseline-indexes.sql` (existing supporting indexes)
- `scripts/sql/10-apply-fix-options.sql` (index recreation as a fix option)
