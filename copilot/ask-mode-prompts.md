# SSMS Copilot — Ask Mode prompts

Copy/paste these into the **GitHub Copilot Ask** pane in SSMS 22.7+. Ask Mode is
read-only: it explains and rewrites text/queries but cannot run modification
statements. Have the relevant query, stored procedure, or execution plan open (or
selected) so Copilot has context.

> Tip: Open the regressed procedure (`Demo.usp_GetRegionalSalesByYear_Regressed`
> or `Demo.usp_GetCustomerInvoiceSummary_Regressed`) before asking, so the
> answers are grounded in the demo code.

## If you're presenting this and you're *not* a DBA

Your job is **not** to write SQL live. It's to run the numbered scripts in order,
paste the prompts below, and narrate the story. The whole demo lands in one
sentence you can repeat:

> "A developer shipped a small change that made a query stop using its index.
> Query Store caught it, and Copilot helps the DBA read the evidence and propose a
> fix — but the DBA and SQL permissions stay in control."

Everything here is **read-only and reversible**, against an isolated demo
database, so you can't break anything live.

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
4. Turn on the plan (**Ctrl+M**), run one call
   (`EXEC Demo.usp_GetRegionalSalesByYear_Regressed @Year = 2015;`), then paste
   prompt **3 (execution plan)** to translate scan vs seek into plain language.
5. Use prompts **4 (partitioning)** and **5 (index)** to show Copilot reasoning
   from evidence instead of jumping to a fix.

## What each prompt should produce (and what to say)

- **1 — Explain / spot concerns.** *Expect:* a summary plus the flag that
  `YEAR(InvoiceDate) = @Year` is non-sargable and forces a scan. *Say:* "It found
  the anti-pattern a DBA looks for, in seconds."
- **2 — Sargable rewrite.** *Expect:* a half-open date range
  (`>= start AND < next start`), same logic. *Say:* "That's the exact fix we ship —
  but we still verify it."
- **3 — Execution plan.** *Expect:* it points to a **scan** reading millions of
  rows as the bottleneck. *Say:* "The plan is the receipt — it shows SQL reading
  the whole table because of the function on the column."
- **4 — Partitioning pushback.** *Expect:* it asks for row counts, access patterns,
  retention/maintenance, and index alignment before recommending anything. *Say:*
  "A senior asks for evidence instead of reflexively partitioning."
- **5 — Index validation.** *Expect:* it raises duplicate indexes, write/storage
  overhead, and column order/selectivity. *Say:* "Indexes aren't free — every one
  slows writes; it lists the checks first."

## Glossary (say it this simply)

- **Index seek vs scan** — seek = jump to the rows you need (fast); scan = read
  every row (slow at 10M rows).
- **Sargable** — a filter that *allows* a seek (column not wrapped in a function).
- **Query Store** — SQL Server's "flight recorder": saves each query's plans and
  runtime stats over time; the source of truth here.
- **Logical reads** — 8 KB pages a query touched; a proxy for "work." A scan has
  far more than a seek.
- **Execution plan** — the recipe SQL used to run the query (where seek vs scan is
  visible).

## Likely questions from a DBA audience (crisp answers)

- **"Does Copilot run my query?"** In Ask mode it can run *read-only* queries to
  answer, but can't modify data or schema. Suggested rewrites are text — you run
  them.
- **"Under whose permissions?"** The login you connected SSMS with. We use a
  least-privilege login on purpose — SQL permissions are the real boundary.
- **"How does it know our schema?"** From the connected database (plus any
  installed `CONSTITUTION.md` / `AGENTS.md`). No connection, no context.
- **"Is the first answer always right?"** No — treat it as a hypothesis and confirm
  with Query Store and the plan before acting.

Remember: the first answer is a starting point. Validate every suggestion against
Query Store, the execution plan, and workload evidence before acting.
