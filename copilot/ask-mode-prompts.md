# SSMS Copilot — Ask Mode prompts

Copy/paste these into the **GitHub Copilot Ask** pane in SSMS 22.7+. Ask Mode is
read-only: it explains and rewrites text/queries but cannot run modification
statements. Have the relevant query, stored procedure, or execution plan open (or
selected) so Copilot has context.

## Place in the story

- **Stage:** the first hands-on Copilot stage in the canonical DBA investigation.
- **Enter from:** the README
  [baseline and regression evidence](../README.md#capture-baseline-and-regression-evidence).
- **This document owns:** the full Ask mode prompts, UI context, and expected
  interpretation.
- **Continue with:** [Agent mode](agent-mode-prompts.md) for the multi-step version,
  then the README [guardrail model](../README.md#guardrails-and-execution-identity)
  and [reviewed-fix validation flow](../README.md#apply-the-reviewed-fix-and-validate).
- **For a live run:** use the condensed [one-page prompt sheet](ssms-demo-prompts.md)
  and return here for explanation and expected output.

> Tip: Open the regressed procedure (`Demo.usp_GetRegionalSalesByYear_Regressed`
> or `Demo.usp_GetCustomerInvoiceSummary_Regressed`) before asking, so the
> answers are grounded in the demo code.

## How to use this stage

Run the numbered scripts in order, paste the prompts below, and compare Copilot's
response with the Query Store and execution-plan evidence.

> **Core takeaway:** A small query change prevented index use. Query Store
> captured the regression, and Copilot helps the DBA interpret the evidence and
> propose a fix while the DBA and SQL permissions remain in control.

The intended flow is read-only and runs against an isolated demo database. Review
all generated SQL and keep the query window connected to WideWorldImporters;
SQL Server permissions remain the enforcement boundary.

## 2-minute SSMS orientation (where to click)

- **Object Explorer** (left panel) is the tree of servers/databases. Expand
  **Databases ▸ WideWorldImporters**.
- **Keep your query window connected to WideWorldImporters.** The database dropdown
  in the toolbar above the query text must say `WideWorldImporters`, not `master`.
  (If Copilot says *"does not have support for this connection context,"* this
  dropdown is the fix.) Easiest: right-click **WideWorldImporters ▸ New Query**.
- **Open the regressed procedure:** Object Explorer ▸ WideWorldImporters ▸
  **Programmability ▸ Stored Procedures**, right-click
  `Demo.usp_GetRegionalSalesByYear_Regressed` ▸ **Modify**.
- **Open Copilot chat:** the **Copilot** badge at SSMS top-right. Keep the mode
  selector on **Ask** for this file.
- **Turn on the execution plan:** press **Ctrl+M** ("Include Actual Execution
  Plan"), then run with **F5**; an **Execution plan** tab appears.

## The one concept to nail: "sargable"

**Sargable** = a `WHERE` condition SQL Server can satisfy with an **index seek**
(jump to the matching rows) instead of a **scan** (read every row). Wrapping the
indexed column in a function breaks it:

- ❌ `WHERE YEAR(InvoiceDate) = 2015` — SQL computes `YEAR()` on every row → scans
  ~10M rows.
- ✅ `WHERE InvoiceDate >= '2015-01-01' AND InvoiceDate < '2016-01-01'` — same
  result, but SQL seeks the index and touches only matching rows.

Analogy for the room: finding a name by flipping to the right page of a phone book
(seek) vs. reading every page (scan). That one difference is the whole demo.

## Explain a procedure / spot concerns
```
Explain what this stored procedure does and identify possible performance concerns.
```

## Make a query sargable
```
Rewrite this query to be more sargable without changing the business logic.
```

## Before prompt 3: capture an execution plan

A rewrite is just *text* — an execution plan only exists once you **run** a query.
Generate one before the next prompt:

1. Press **Ctrl+M** ("Include Actual Execution Plan").
2. Run the **regressed** procedure once (**F5**):
   ```sql
   EXEC Demo.usp_GetRegionalSalesByYear_Regressed @Year = 2015;
   ```
3. Click the **Execution plan** tab next to *Results* and keep it in the active
   window so Copilot has it as context. This is the *slow* plan (a full **scan**)
   that prompt 3 explains.

## Interpret an execution plan
```
Based on this execution plan, explain the likely bottleneck in simple DBA terms.
```

## Push back on partitioning
```
What evidence would you need before recommending partitioning for this table?
```

## Validate an index recommendation
```
Review this index recommendation and tell me what else I should validate before creating it.
```

---

### How to run these in the demo
1. Open `Demo.usp_GetRegionalSalesByYear_Regressed` in a query window connected to
   **WideWorldImporters**.
2. Paste prompt **1 (Explain)** — Copilot should call out `YEAR(InvoiceDate) =
   @Year` as non-sargable.
3. Paste prompt **2 (sargable rewrite)** — compare its suggestion to
   `Demo.usp_GetRegionalSalesByYear_Fixed` (they should match in spirit).
4. **Capture an execution plan** — a rewrite produces none, so generate one: press
   **Ctrl+M**, then run the regressed proc with **F5**
   (`EXEC Demo.usp_GetRegionalSalesByYear_Regressed @Year = 2015;`). An **Execution
   plan** tab appears showing a full **scan**.
5. With that plan in the active window, paste prompt **3 (execution plan)** to
   translate the scan into plain language.
6. *(Optional — closes the loop)* Run the **fixed** proc the same way to watch the
   plan flip to a **seek**
   (`EXEC Demo.usp_GetRegionalSalesByYear_Fixed @Year = 2015;`). If the index was
   dropped earlier, recreate it first with Section B of
   `scripts/sql/10-apply-fix-options.sql`.
7. Use prompts **4 (partitioning)** and **5 (index)** to show Copilot reasoning
   from evidence instead of jumping to a fix.

## Expected output and DBA validation

- **1 — Explain / spot concerns.** *Expect:* a summary plus the flag that
  `YEAR(InvoiceDate) = @Year` is non-sargable and forces a scan. *Validation:*
  confirm the anti-pattern in the procedure and execution plan.
- **2 — Sargable rewrite.** *Expect:* a half-open date range
  (`>= start AND < next start`), same logic. *Validation:* confirm equivalent
  results, then compare runtime evidence.
- **3 — Execution plan.** *Expect:* it points to a **scan** reading millions of
  rows as the bottleneck. *Validation:* confirm that the plan reads the whole
  table because the function is applied to the filtered column.
- **4 — Partitioning pushback.** *Expect:* it asks for row counts, access patterns,
  retention/maintenance, and index alignment before recommending anything.
  *Decision point:* require evidence instead of reflexively partitioning.
- **5 — Index validation.** *Expect:* it raises duplicate indexes, write/storage
  overhead, and column order/selectivity. *Decision point:* account for write and
  storage cost before creating another index.

## Glossary

- **Index seek vs scan** — seek = jump to the rows you need (fast); scan = read
  every row (slow at 10M rows).
- **Sargable** — a filter that *allows* a seek (column not wrapped in a function).
- **Query Store** — SQL Server's "flight recorder": saves each query's plans and
  runtime stats over time; the source of truth here.
- **Logical reads** — 8 KB pages a query touched; a proxy for "work." A scan has
  far more than a seek.
- **Execution plan** — the recipe SQL used to run the query (where seek vs scan is
  visible).

## Likely DBA questions

- **"Does Copilot run my query?"** Ask mode uses a read-only classification for
  generated queries. Suggested rewrites are text for you to review and run. That
  classification is a product safeguard, not a replacement for least-privilege
  SQL permissions.
- **"Under whose permissions?"** The login you connected SSMS with. We use a
  least-privilege login on purpose — SQL permissions are the real boundary.
- **"How does it know our schema?"** From the connected database (plus any
  installed `CONSTITUTION.md` / `AGENTS.md`). No connection, no context.
- **"Is the first answer always right?"** No — treat it as a hypothesis and confirm
  with Query Store and the plan before acting.

Remember: the first answer is a starting point. Validate every suggestion against
Query Store, the execution plan, and workload evidence before acting.
