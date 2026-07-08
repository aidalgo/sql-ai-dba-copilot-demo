# SSMS object-level instructions — AGENTS.md extended properties

In addition to the database-level `CONSTITUTION.md` (see
[ssms-database-constitution.md](ssms-database-constitution.md)), SSMS Copilot reads
**object-level** instructions stored as extended properties named **`AGENTS.md`**
on individual objects (tables, columns, procedures). These follow the
[agents.md](https://agents.md) convention and give Copilot local, object-specific
context. `scripts/sql/15-install-copilot-constitution.sql` installs the properties
below.

Precedence (most specific wins for that object): column `AGENTS.md` →
table/proc `AGENTS.md` → database `CONSTITUTION.md`.

## On `Demo.LargeInvoiceFact` (table)

```markdown
# Demo.LargeInvoiceFact

Amplified, denormalized invoice fact table used by the performance demo
(~10M rows). Rows are projected from WideWorldImporters Sales.Invoices /
Sales.InvoiceLines, with invoice dates spread across many years.

- Filter on `InvoiceDate` with a **sargable half-open range**
  (`InvoiceDate >= @start AND InvoiceDate < @end`). Do **not** wrap `InvoiceDate`
  in functions like `YEAR(InvoiceDate) = @y` — that prevents index seeks.
- Supporting index `IX_Demo_LargeInvoiceFact_InvoiceDate` (when present) makes the
  range predicate a seek. `IX_Demo_LargeInvoiceFact_CustomerID` supports
  per-customer lookups.
- This is demo data. Read-only for investigation.
```

## On the regressed procedures

```markdown
# Demo.usp_*_Regressed

This is the intentionally REGRESSED variant used to demonstrate a performance
problem. It uses a non-sargable predicate (`YEAR(InvoiceDate) = @Year`) which
forces a full scan. The corrected logic lives in the matching `_Fixed` procedure
(sargable date range). When asked to fix, recommend the sargable rewrite plus the
supporting index — not partitioning.
```

## On the baseline / fixed procedures

```markdown
# Demo.usp_*_Baseline / Demo.usp_*_Fixed

Healthy variant: uses a sargable half-open date range so the optimizer can seek on
IX_Demo_LargeInvoiceFact_InvoiceDate. Use this as the reference for what "good"
looks like when comparing Query Store metrics.
```

---

### Verifying installed properties
```sql
-- Database-level CONSTITUTION.md
SELECT name, value FROM sys.extended_properties WHERE class = 0 AND name = 'CONSTITUTION.md';

-- Object-level AGENTS.md
SELECT OBJECT_SCHEMA_NAME(major_id) AS [schema], OBJECT_NAME(major_id) AS [object], value
FROM sys.extended_properties
WHERE class = 1 AND name = 'AGENTS.md';
```
