# Advanced scenarios (optional "Act 2")

The main demo proves Copilot *fits the DBA workflow* on a common, easy-to-spot
problem. These optional add-ons make it prove Copilot is also **powerful and
broad**: a genuinely subtle bug, ad-hoc query writing, a "catch the wrong answer"
trust moment, and Copilot reaching **beyond the database** via an MCP tool.

Run these **after** the main demo, in the same SSMS session, connected to
**WideWorldImporters**. They build on the state the main demo already created
(the ~10M-row `Demo.LargeInvoiceFact`, its indexes, Query Store history, and the
installed `CONSTITUTION.md` / skills).

> Everything here is **additive and reversible**. New objects live in the `Demo`
> schema and are removed by the [Cleanup](#cleanup) block at the end — the main
> demo objects and data are untouched.

## Contents
- [If you're presenting this and you're *not* a DBA](#if-youre-presenting-this-and-youre-not-a-dba)
- [Prerequisites](#prerequisites)
- [Scenario A — A genuinely hard problem](#scenario-a--a-genuinely-hard-problem)
  - [A1 — Implicit conversion (recommended, deterministic)](#a1--implicit-conversion-recommended-deterministic)
  - [A2 — Parameter sniffing (optional, more advanced)](#a2--parameter-sniffing-optional-more-advanced)
- [Scenario B — Ad-hoc NL-to-SQL (breadth)](#scenario-b--ad-hoc-nl-to-sql-breadth)
- [Scenario C — Catch the wrong answer (trust)](#scenario-c--catch-the-wrong-answer-trust)
- [Scenario D — Reach beyond the database with an MCP tool](#scenario-d--reach-beyond-the-database-with-an-mcp-tool)
- [Going deeper: other DBA domains](#going-deeper-other-dba-domains)
- [Cleanup](#cleanup)

## If you're presenting this and you're *not* a DBA

Same job as the main demo: **run the setup block, paste the prompt, narrate.** The
difference is these problems are subtler, so let Copilot do the explaining and use
the "what to say" lines to frame *why it matters*. Rehearse each once before going
live — especially Scenario A2 (parameter sniffing) and Scenario D (MCP), which have
more moving parts.

## Prerequisites

- You finished the main demo (Query Store has the baseline/regressed/fixed windows;
  `Demo.LargeInvoiceFact` is loaded; base indexes exist).
- **SSMS 22.7+** signed in to Copilot, connected to **WideWorldImporters** (not
  `master`). Turn on the actual plan with **Ctrl+M**.
- Scenario D needs **Agent Mode** and one **MCP server** (details in that section).

---

## Scenario A — A genuinely hard problem

The main demo's `YEAR(InvoiceDate)` is a "layup" a senior DBA spots instantly.
These are the subtle bugs that actually cost people hours — and where Copilot
reading the execution plan earns its keep.

### A1 — Implicit conversion (recommended, deterministic)

**The trap:** a developer passes a customer *number* (`int`) into a lookup whose
column is a *code* (`varchar`). Because `int` outranks `varchar` in SQL Server's
data-type precedence, SQL silently converts **the whole column to int on every
row** — an *implicit conversion* that turns an index seek into a full scan. It
reproduces every time, on any collation, and almost nobody sees it without the plan.

**Setup** (idempotent; additive. ~10M rows: the column + index build take a minute or two):
```sql
USE WideWorldImporters;
GO
-- A varchar "reference code" derived from CustomerID, plus an index on it.
IF COL_LENGTH('Demo.LargeInvoiceFact', 'CustomerRef') IS NULL
    ALTER TABLE Demo.LargeInvoiceFact
        ADD CustomerRef AS CONVERT(varchar(20), CustomerID) PERSISTED;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_Demo_LargeInvoiceFact_CustomerRef'
                 AND object_id = OBJECT_ID(N'Demo.LargeInvoiceFact'))
    CREATE NONCLUSTERED INDEX IX_Demo_LargeInvoiceFact_CustomerRef
        ON Demo.LargeInvoiceFact (CustomerRef)
        INCLUDE (InvoiceDate, LineTotal)
        WITH (DATA_COMPRESSION = PAGE, ONLINE = OFF);
GO
UPDATE STATISTICS Demo.LargeInvoiceFact WITH FULLSCAN;
GO
-- BAD: @CustomerId is int, so SQL converts the varchar COLUMN to int
--      (CONVERT_IMPLICIT on the column) -> the index can't seek -> SCAN.
CREATE OR ALTER PROCEDURE Demo.usp_GetInvoicesByCustomerRef_BadType
    @CustomerId int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Invoices = COUNT_BIG(*), TotalSales = SUM(f.LineTotal)
    FROM Demo.LargeInvoiceFact AS f
    WHERE f.CustomerRef = @CustomerId;     -- implicit conversion (int vs varchar) -> scan
END;
GO
-- GOOD: @CustomerRef matches the column type (varchar) -> index SEEK.
CREATE OR ALTER PROCEDURE Demo.usp_GetInvoicesByCustomerRef_GoodType
    @CustomerRef varchar(20)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Invoices = COUNT_BIG(*), TotalSales = SUM(f.LineTotal)
    FROM Demo.LargeInvoiceFact AS f
    WHERE f.CustomerRef = @CustomerRef;    -- matched types -> seek
END;
GO
```

**Show the difference** (press **Ctrl+M** first so the actual plan is captured):
```sql
EXEC Demo.usp_GetInvoicesByCustomerRef_BadType  @CustomerId  = 100;    -- SCAN (implicit conversion)
EXEC Demo.usp_GetInvoicesByCustomerRef_GoodType @CustomerRef = '100';  -- SEEK
```
In the **Execution plan** tab, the bad one shows an **Index/Table Scan** with a
warning (the yellow "!" ) and a `CONVERT_IMPLICIT(...)` on `CustomerRef`; the good
one shows an **Index Seek**.

**Ask Mode** (open `Demo.usp_GetInvoicesByCustomerRef_BadType`, run it with the plan on):
```
Based on this execution plan, why is this query scanning instead of seeking? Be specific about data types.
```
```
Rewrite the procedure to remove the implicit conversion without changing the results.
```

**Agent Mode** (read-only investigation):
```
Investigate why Demo.usp_GetInvoicesByCustomerRef_BadType is slow. Use Query Store and the execution plan. Identify the root cause precisely and propose a fix. Do not change anything.
```

- **Expect:** Copilot names the **implicit conversion** (`int` parameter vs
  `varchar` column), explains it forces a column-side `CONVERT_IMPLICIT` that
  blocks the seek, and proposes matching the parameter type (the `_GoodType` shape).
- **Say:** "This is the kind of bug that hides in plain sight — the query *looks*
  fine and even returns the right answer. Copilot found it in the plan in seconds;
  most people would stare at it for an hour."
- **Why it matters:** it proves Copilot handles *subtle* problems, not just the
  obvious `YEAR()` one — the difficulty jump the main demo is missing.

### A2 — Parameter sniffing (optional, more advanced)

**The trap:** a procedure's best plan depends on the *parameter value*. SQL compiles
and caches a plan for the **first** value it sees ("sniffs") and reuses it — great
for that value, terrible for a very different one.

> ⚠️ Parameter sniffing depends on data skew and the plan cache, so it's less
> deterministic than A1. **Rehearse it** and pick customers with very different row
> counts. If it won't reproduce on your data, use A1 as your hard problem.

**Setup:**
```sql
USE WideWorldImporters;
GO
CREATE OR ALTER PROCEDURE Demo.usp_CustomerInvoices_Sniff
    @CustomerID int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT f.InvoiceFactID, f.InvoiceDate, f.Quantity, f.LineTotal
    FROM Demo.LargeInvoiceFact AS f
    WHERE f.CustomerID = @CustomerID
    ORDER BY f.InvoiceDate DESC;
END;
GO
-- Pick a HIGH-frequency and a LOW-frequency customer (note the two IDs):
SELECT TOP (1) BigCustomerID   = CustomerID, Rows = COUNT_BIG(*)
FROM Demo.LargeInvoiceFact GROUP BY CustomerID ORDER BY COUNT_BIG(*) DESC;
SELECT TOP (1) SmallCustomerID = CustomerID, Rows = COUNT_BIG(*)
FROM Demo.LargeInvoiceFact GROUP BY CustomerID ORDER BY COUNT_BIG(*) ASC;
```

**Reproduce** (swap in the two IDs from above):
```sql
EXEC sys.sp_recompile N'Demo.usp_CustomerInvoices_Sniff';        -- clear this proc's cached plan
EXEC Demo.usp_CustomerInvoices_Sniff @CustomerID = <SmallCustomerID>;  -- compiles a plan tuned for FEW rows
EXEC Demo.usp_CustomerInvoices_Sniff @CustomerID = <BigCustomerID>;    -- reuses it -> slow for MANY rows
EXEC Demo.usp_CustomerInvoices_Sniff @CustomerID = <BigCustomerID> WITH RECOMPILE;  -- fresh compile -> better plan
```

**Agent Mode:**
```
Demo.usp_CustomerInvoices_Sniff runs fast for some customers and slow for others with the same code. Using Query Store, determine whether this is parameter sniffing, and lay out the fix options with trade-offs. Do not change anything.
```

- **Expect:** Copilot recognizes **parameter sniffing** (one `query_id`, one cached
  plan, wildly different durations by parameter) and lists fixes: `OPTION(RECOMPILE)`,
  `OPTIMIZE FOR UNKNOWN`, `OPTIMIZE FOR (@CustomerID = <typical>)`, a **Query Store
  hint** (no code change — see `scripts/sql/10-apply-fix-options.sql` Section E), or
  **plan forcing** (Section D).
- **Say:** "Same code, opposite performance depending on the input — this is the
  problem juniors can't name. Copilot names it *and* gives the menu, including the
  no-code-change options a DBA reaches for in production."

---

## Scenario B — Ad-hoc NL-to-SQL (breadth)

No setup. Shows Copilot as a **query-writing** partner, not just a tuner — the
everyday value a DBA/analyst gets. Use Ask Mode, connected to WideWorldImporters.

```
Write a T-SQL query against Demo.LargeInvoiceFact that returns the top 10 customers by total sales in 2015, including the customer's city name. Use a sargable date filter.
```
```
Now add each customer's invoice count and average line total for 2015, and only include customers with more than 50 invoices.
```
```
Turn this into a stored procedure Demo.usp_TopCustomersByYear that takes @Year int, keeping the date filter sargable.
```

- **Expect:** correct, schema-aware T-SQL — it joins `Demo.LargeInvoiceFact` to
  `Application.Cities` on `CityID` for the city name, uses a half-open date range
  (not `YEAR()`), and adds the `HAVING COUNT(*) > 50` and the parameterized proc on
  request.
- **Say:** "Notice it discovered the join to the city dimension itself, and it kept
  the date filter sargable *without being asked* — it learned that from the
  instructions we installed. And it iterates: I refined the request three times in
  plain English."
- **Do:** review the generated proc before running it — the discipline still applies.

---

## Scenario C — Catch the wrong answer (trust)

The most persuasive moment for a skeptical audience isn't Copilot being right — it's
watching a DBA **reject a plausible-but-wrong AI-style suggestion with evidence.**
We hand Copilot a shiny bad idea and let the installed skills + Query Store shoot it
down.

**Over-eager index (Ask Mode):**
```
A teammate wants to speed up the slow reporting query by adding this index. Should we create it? What's wrong with it?
CREATE NONCLUSTERED INDEX IX_Everything ON Demo.LargeInvoiceFact
    (CustomerID, CityID, StockItemID, InvoiceDate, Quantity, UnitPrice, LineTotal, SalespersonPersonID);
```
- **Expect** (guided by the `index-recommendation-validation` skill): it flags the
  index as **near-duplicate** of existing indexes, **far too wide** (write + storage
  overhead), the **wrong leading column** for a date-range predicate, and — the
  kicker — that **no index fixes a non-sargable or implicit-conversion query** in the
  first place.

**"Just partition it" (Ask or Agent):**
```
Someone suggests partitioning Demo.LargeInvoiceFact by year to fix the slow date queries. Is that the right fix here, and what evidence would you need before recommending it?
```
- **Expect** (guided by the `partitioning-assessment` skill): partitioning is **not**
  the right primary fix; the sargable rewrite + supporting index is. It asks for row
  counts, access patterns, retention/maintenance, and index alignment first.

- **Say:** "The first idea is often the wrong idea. The database's own instructions
  and Query Store keep the AI honest — it talked us *out* of an expensive change and
  back to the simple, correct one. That's the guardrail working."

---

## Scenario D — Reach beyond the database with an MCP tool

Agent Mode can use **MCP servers** to act outside SQL Server — here, to **file a
ticket** from the investigation findings. This shows Copilot fitting into the real
ops workflow, not just the query window.

> Only **Agent Mode** supports MCP. Newly added MCP tools are **disabled by
> default** — you must enable them in the **Tools** panel of the Copilot chat.
> Rehearse this once before presenting, and have a fallback (below).

Pick **one** server:

### Option D1 — Filesystem server (offline mock, recommended)
A free, official server that writes the "ticket" as a local Markdown file. No
external account; fully offline.

- **Prereq:** Node.js LTS on the jumpbox (`winget install OpenJS.NodeJS.LTS`) and a
  folder, e.g. `C:\Demo\tickets`.
- **Add it** — in the Copilot chat, **Tools** icon → green **+** → **Add custom MCP
  server**, choose **stdio**, and set:
  - Command: `npx`
  - Args: `-y  @modelcontextprotocol/server-filesystem  C:\Demo\tickets`
- Or add it to `%USERPROFILE%\.mcp.json`:
  ```json
  {
    "servers": {
      "filesystem": {
        "type": "stdio",
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-filesystem", "C:\\Demo\\tickets"]
      }
    }
  }
  ```
- **Enable** the filesystem write tool in the Tools panel.

**Agent prompt:**
```
Using the filesystem tool, create a ticket at C:\Demo\tickets\DBA-Findings-implicit-conversion.md summarizing our investigation: title, affected procedure, the query_id and plan_id from Query Store, the root cause (implicit conversion, int vs varchar), the recommended fix, validation steps, and rollback. Then show me the file path and its contents.
```

### Option D2 — GitHub issue (real ticket, if you use GitHub)
GitHub Issues *is* a free ticketing system, and this repo is on GitHub — so "I don't
have a ticket system" is covered. Uses the hosted GitHub MCP server (no local
install), but opens a **real issue** in your repo.

- **Add it** to `%USERPROFILE%\.mcp.json` (SSMS shows an **Authentication Required**
  link to sign in):
  ```json
  {
    "servers": {
      "github": {
        "url": "https://api.githubcopilot.com/mcp/"
      }
    }
  }
  ```
- **Enable** the "create issue" tool in the Tools panel.

**Agent prompt:**
```
Using the GitHub tool, open an issue in the aidalgo/sql-ai-dba-copilot-demo repository titled "DBA: implicit-conversion regression on Demo.LargeInvoiceFact" with a body that summarizes the root cause, the affected procedure, the recommended fix, validation, and rollback. Return the issue URL.
```

- **Expect:** Agent calls the MCP tool (you approve it) and creates the ticket —
  file or issue — then returns the path/URL.
- **Say:** "The same assistant that read Query Store just filed the ticket for the
  team. It reaches beyond the database into our workflow — still through an approval,
  still under our control."
- **Fallback (if MCP misbehaves live):** show the Tools panel with the server added,
  then paste a pre-written ticket. The point — Copilot reaching into your ops
  tooling — still lands.

---

## Going deeper: other DBA domains

The demo focuses on query performance, but Copilot in SSMS is schema- and
**DMV-aware**, so it helps across the rest of a DBA's world. These are optional,
**read-only, no-setup** prompts you can drop in live to prove breadth.

> Copilot **investigates, explains, and drafts T-SQL — you review and run** anything
> that changes state. It won't click through config wizards or take destructive
> actions. Instance-level DMVs need `VIEW SERVER STATE`; the backup and Agent-job
> prompts need access to `msdb`.

**Best two to show live** (deterministic, no setup, and they land with DBAs):
**blocking** and **wait-stats**.

### Blocking — who is blocking whom, right now
```
Show the current blocking chain from sys.dm_exec_requests and sys.dm_os_waiting_tasks: the head blocker, who is blocked, the blocked statement, and the lock resource.
```

### Wait-stats triage — where the instance spends its time
```
Summarize the top non-benign waits from sys.dm_os_wait_stats (exclude the usual benign ones) and, for each, tell me what to investigate next.
```

### Deadlocks — read them from system_health
```
Read recent deadlocks from the system_health Extended Events session and summarize the victims, the resources involved, and a likely fix (index or access-order change).
```

### Backups — RPO gaps and a restore script
```
Query msdb.dbo.backupset to list each database's last full, differential, and log backup, and flag any database with no backup in the last 24 hours.
```
Follow-up: `Generate the RESTORE sequence (full + latest diff + log chain) to recover DB X to 14:30 today.` — a script you review and run.

### Security — permission audit
```
List every principal with db_owner, CONTROL, or ALTER on this database, plus any orphaned users (database principals with no matching server login).
```

### HA/DR — Always On health
```
Using sys.dm_hadr_database_replica_states and sys.availability_groups, show each AG replica's synchronization health and flag any secondary with a growing redo or log-send queue.
```

### tempdb — consumers and contention
```
Which sessions consume the most tempdb (sys.dm_db_session_space_usage / task_space_usage), and is there PFS/GAM allocation contention? Recommend whether to add tempdb files.
```

### Capacity — file growth and runway
```
Report data/log file size, free space, and autogrowth per database (sys.master_files + FILEPROPERTY), and project when the data drive fills based on backup-size growth over the last 90 days.
```

### Migrations — what blocks Azure SQL
```
Scan this database for features that block migration to Azure SQL Database (cross-database references, Agent-job dependencies, unsupported features, compatibility level) and list them with a suggested remediation.
```
The Database Migration Assistant / Azure Migrate remain the authoritative tools.

### SQL Agent jobs — recent failures
```
From msdb job history (sysjobs / sysjobhistory / sysjobsteps), list Agent jobs that failed in the last 7 days with the failing step and error, plus any long-running or disabled jobs.
```

**Two multipliers to mention:** pair any of these with **Agent Mode + MCP** (e.g.,
file the wait-stats or deadlock finding as a ticket — Scenario D), and bake your
team's preferred DMV queries into a database `CONSTITUTION.md` so Copilot answers
ops questions your way.

---

## Cleanup

Removes only the advanced-scenario objects. The main demo (fact data, base indexes,
base procedures, Query Store history, constitution) stays intact.

```sql
USE WideWorldImporters;
GO
DROP PROCEDURE IF EXISTS Demo.usp_GetInvoicesByCustomerRef_BadType;
DROP PROCEDURE IF EXISTS Demo.usp_GetInvoicesByCustomerRef_GoodType;
DROP PROCEDURE IF EXISTS Demo.usp_CustomerInvoices_Sniff;
DROP PROCEDURE IF EXISTS Demo.usp_TopCustomersByYear;   -- only if you created it in Scenario B
DROP INDEX IF EXISTS IX_Demo_LargeInvoiceFact_CustomerRef ON Demo.LargeInvoiceFact;
IF COL_LENGTH('Demo.LargeInvoiceFact', 'CustomerRef') IS NOT NULL
    ALTER TABLE Demo.LargeInvoiceFact DROP COLUMN CustomerRef;
GO
-- If you applied Query Store hints / plan forcing in Scenario A2, clear them
-- (fill in the query_id / plan_id from your Query Store report):
-- EXEC sys.sp_query_store_clear_hints  @query_id = <id>;
-- EXEC sys.sp_query_store_unforce_plan @query_id = <id>, @plan_id = <id>;
GO
PRINT '[OK] Advanced-scenario objects removed. Main demo is intact.';
GO
```
