/* =============================================================================
   15-install-copilot-constitution.sql

   Purpose : Configure SSMS GitHub Copilot for this database the *native* way:
               1. Create GHCP_DB_User -- a low-privilege, read-only user that
                  MODELS least privilege for AI-assisted investigation.
               2. Grant it least-privilege read access (+ VIEW DATABASE STATE so
                  it can read Query Store DMVs).
               3. Grant the current login IMPERSONATE on GHCP_DB_User (only needed
                  for the OPTIONAL execution pin -- see section 7 at the end).
               4. Install the database-level CONSTITUTION.md extended property
                  (BODY ONLY -- no agentExecuteAsUser, so Copilot runs under the
                  login you connect SSMS with).
               5. Install object-level AGENTS.md extended properties on the demo
                  table and procedures.

   Least privilege : Copilot in SSMS has NO separate permissions -- it runs SQL
             under the account you connect with, and SQL Server permission
             enforcement (not Copilot, not the Agent Mode approval prompt) is the
             security boundary. GHCP_DB_User is an illustrative database user for
             a direct permission test; the body-only constitution does not switch
             the live Copilot session to it. Customer adoption should use a
             dedicated least-privilege identity. Pinning Copilot to one fixed
             identity via agentExecuteAsUser is an optional pattern in section 7.

   Run as  : db_owner (or a login with CREATE USER, GRANT, and ALTER on the demo
             objects). Run this ONCE per demo database.
   Safe    : Creates a read-only principal and adds extended properties. Makes no
             data/schema changes to WideWorldImporters tables.
   Idempotent : Re-runnable; drops-then-adds the extended properties and skips the
             user/grants if already present.

   See copilot/database-instructions.md for the human-readable architecture,
   execution-context explanation, and the exact installation source below.
   ============================================================================= */
SET NOCOUNT ON;
USE WideWorldImporters;
GO

/* ---------------------------------------------------------------------------
   1) Low-privilege investigation user.
   --------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'GHCP_DB_User' AND type = N'S')
BEGIN
    CREATE USER GHCP_DB_User WITHOUT LOGIN;
    PRINT '[OK]  Created database user GHCP_DB_User (WITHOUT LOGIN).';
END
ELSE
    PRINT '[INFO] GHCP_DB_User already exists.';
GO

/* ---------------------------------------------------------------------------
   2) Least-privilege grants. SELECT on the demo + WWI schemas the demo reads,
      EXECUTE on Demo procedures, and VIEW DATABASE STATE for Query Store DMVs.
      No INSERT/UPDATE/DELETE/ALTER/DROP/CREATE are granted.
   --------------------------------------------------------------------------- */
GRANT SELECT ON SCHEMA::Demo        TO GHCP_DB_User;
GRANT SELECT ON SCHEMA::Sales       TO GHCP_DB_User;
GRANT SELECT ON SCHEMA::Warehouse   TO GHCP_DB_User;
GRANT SELECT ON SCHEMA::Application TO GHCP_DB_User;
GRANT EXECUTE ON SCHEMA::Demo       TO GHCP_DB_User;   -- run read-only demo procs
GRANT VIEW DATABASE STATE           TO GHCP_DB_User;   -- read sys.query_store_* and other DMVs
PRINT '[OK]  Granted least-privilege read access to GHCP_DB_User.';
GO

/* ---------------------------------------------------------------------------
   3) Let the CURRENT login impersonate GHCP_DB_User. This is ONLY needed if you
      enable the OPTIONAL execution pin in section 7 (the default body-only
      constitution does not use EXECUTE AS). sysadmin/dbo can already impersonate,
      so this only grants for non-dbo users.
   --------------------------------------------------------------------------- */
IF USER_NAME() <> N'dbo'
BEGIN
    DECLARE @grant nvarchar(max) = N'GRANT IMPERSONATE ON USER::GHCP_DB_User TO ' + QUOTENAME(USER_NAME()) + N';';
    EXEC sys.sp_executesql @grant;
    PRINT '[OK]  Granted IMPERSONATE on GHCP_DB_User to ' + USER_NAME() + '.';
END
ELSE
    PRINT '[INFO] Connected as dbo; IMPERSONATE grant not required for this login.';
GO

/* ---------------------------------------------------------------------------
   4) Database-level CONSTITUTION.md (highest-precedence Copilot instructions).
      BODY ONLY: no agentExecuteAsUser front matter, so Copilot runs under the
      account you connect SSMS with. In this demo, GHCP_DB_User is tested
      separately to illustrate least privilege. SQL Server permissions, not
      Copilot, are the security boundary.

      IMPLEMENTATION REFERENCE -- how you WOULD pin Copilot to a specific user:
      add YAML front matter to the TOP of the @constitution value below, e.g.
          ---
           agentExecuteAsUser: <a low-privilege database user or SQL login>
          ---
        Grant the connected account IMPERSONATE on that identity. We leave it out on
        purpose so the default connected-account execution model remains visible.
        See section 7 and copilot/database-instructions.md before enabling it.
   --------------------------------------------------------------------------- */
-- NOTE: sp_addextendedproperty's @value is sql_variant, which cannot hold
-- nvarchar(max) (Msg 206). Keep these docs within nvarchar(4000) / 8000 bytes.
DECLARE @constitution nvarchar(4000) = N'# Database constitution — AI-assisted DBA investigation (WideWorldImporters demo)

You are assisting a Database Administrator who is investigating SQL Server
performance using **Query Store as the source of truth**. Behave like a careful,
senior DBA.

## Operating principles
1. Investigation is read-only by default. Prefer querying Query Store views
   (sys.query_store_query, sys.query_store_plan, sys.query_store_runtime_stats,
   sys.query_store_runtime_stats_interval, sys.query_store_query_text) and other
   DMVs over guessing.
2. Never modify data or schema unless the human explicitly asks for it in this
   session. Do not run INSERT, UPDATE, DELETE, MERGE, TRUNCATE, CREATE, ALTER,
   DROP, or grant/revoke statements during investigation.
3. Propose changes as reviewable T-SQL, with: when to use it, the risk, how to
   validate it, and how to roll it back. Let the DBA execute it manually in a
   test environment first.
4. Cite evidence. Reference query_id, plan_id, time windows, and the runtime
   metrics (duration, CPU, logical reads, execution count, plan count) that
   support each conclusion.
5. Diagnose root cause before recommending fixes. Common causes here:
   non-sargable predicates (e.g. YEAR(col) = @y), missing/dropped indexes, stale
   statistics, and plan changes (seek to scan).
6. Prefer the simplest safe fix: make the predicate sargable and add/restore a
   supporting index before considering plan forcing, Query Store hints, or
   partitioning.
7. Partitioning is not a generic tuning fix. Only discuss it with evidence from
   row counts, date/range access patterns, retention/maintenance needs, and index
   alignment. Recommend simpler fixes first.
8. Return findings as a DBA review table when asked to investigate: query,
   query_id, plan_id, metric deltas, likely cause, recommended next action, risk,
   validation, rollback.

## Hard guardrails
- You run under the connected DBA login, which should be a least-privilege
  principal. If an action is blocked by permissions, report it and suggest the
  manual step — do not attempt to escalate privileges.
- Approvals in Agent Mode are not a security boundary; SQL permissions are.
- This is a non-production demo database. Still, treat every recommendation as if
  it were going to production: review, test, validate, and keep a rollback.';

IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 0 AND name = N'CONSTITUTION.md')
    EXEC sys.sp_dropextendedproperty @name = N'CONSTITUTION.md';
EXEC sys.sp_addextendedproperty @name = N'CONSTITUTION.md', @value = @constitution;
PRINT '[OK]  Installed database-level CONSTITUTION.md extended property.';
GO

/* ---------------------------------------------------------------------------
   5) Object-level AGENTS.md properties on the demo table and procedures.
   --------------------------------------------------------------------------- */

-- 5a) Demo.LargeInvoiceFact (table)
DECLARE @factDoc nvarchar(4000) = N'# Demo.LargeInvoiceFact

Amplified, denormalized invoice fact table used by the performance demo (~10M
rows), projected from WideWorldImporters Sales.Invoices / Sales.InvoiceLines with
invoice dates spread across many years.

- Filter on InvoiceDate with a SARGABLE half-open range
  (InvoiceDate >= @start AND InvoiceDate < @end). Do NOT wrap InvoiceDate in
  functions like YEAR(InvoiceDate) = @y — that prevents index seeks.
- IX_Demo_LargeInvoiceFact_InvoiceDate (when present) makes the range a seek;
  IX_Demo_LargeInvoiceFact_CustomerID supports per-customer lookups.
- Demo data. Read-only for investigation.';

IF OBJECT_ID(N'Demo.LargeInvoiceFact', N'U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM sys.extended_properties
               WHERE class = 1 AND name = N'AGENTS.md' AND major_id = OBJECT_ID(N'Demo.LargeInvoiceFact'))
        EXEC sys.sp_dropextendedproperty @name = N'AGENTS.md',
             @level0type = N'SCHEMA', @level0name = N'Demo',
             @level1type = N'TABLE',  @level1name = N'LargeInvoiceFact';
    EXEC sys.sp_addextendedproperty @name = N'AGENTS.md', @value = @factDoc,
         @level0type = N'SCHEMA', @level0name = N'Demo',
         @level1type = N'TABLE',  @level1name = N'LargeInvoiceFact';
    PRINT '[OK]  Installed AGENTS.md on Demo.LargeInvoiceFact.';
END
GO

-- 5b) Procedures: pick the right note by name suffix.
DECLARE @regDoc nvarchar(4000) = N'# Demo.usp_*_Regressed

Intentionally REGRESSED variant used to demonstrate a performance problem. It uses
a non-sargable predicate (YEAR(InvoiceDate) = @Year) which forces a full scan. The
corrected logic lives in the matching _Fixed procedure (sargable date range). When
asked to fix, recommend the sargable rewrite plus the supporting index — not
partitioning.';

DECLARE @goodDoc nvarchar(4000) = N'# Demo.usp_*_Baseline / Demo.usp_*_Fixed

Healthy variant: uses a sargable half-open date range so the optimizer can seek on
IX_Demo_LargeInvoiceFact_InvoiceDate. Use this as the reference for what "good"
looks like when comparing Query Store metrics.';

DECLARE @procName sysname, @doc nvarchar(4000);
DECLARE proc_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.objects
    WHERE schema_id = SCHEMA_ID(N'Demo') AND type = N'P' AND name LIKE N'usp[_]%';

OPEN proc_cur;
FETCH NEXT FROM proc_cur INTO @procName;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @doc = CASE
                   WHEN @procName LIKE N'%[_]Regressed' THEN @regDoc
                   WHEN @procName LIKE N'%[_]Fixed'     THEN @goodDoc
                   WHEN @procName LIKE N'%[_]Baseline'  THEN @goodDoc
                   ELSE NULL
               END;
    IF @doc IS NOT NULL
    BEGIN
        IF EXISTS (SELECT 1 FROM sys.extended_properties
                   WHERE class = 1 AND name = N'AGENTS.md'
                     AND major_id = OBJECT_ID(QUOTENAME(N'Demo') + N'.' + QUOTENAME(@procName)))
            EXEC sys.sp_dropextendedproperty @name = N'AGENTS.md',
                 @level0type = N'SCHEMA',    @level0name = N'Demo',
                 @level1type = N'PROCEDURE', @level1name = @procName;
        EXEC sys.sp_addextendedproperty @name = N'AGENTS.md', @value = @doc,
             @level0type = N'SCHEMA',    @level0name = N'Demo',
             @level1type = N'PROCEDURE', @level1name = @procName;
    END
    FETCH NEXT FROM proc_cur INTO @procName;
END
CLOSE proc_cur;
DEALLOCATE proc_cur;
PRINT '[OK]  Installed AGENTS.md on the Demo procedures.';
GO

/* ---------------------------------------------------------------------------
   6) Verify what was installed.
   --------------------------------------------------------------------------- */
PRINT '== Installed Copilot instructions ==';
SELECT scope = 'DATABASE', object_name = DB_NAME(), property = name, value_preview = LEFT(CONVERT(nvarchar(max), value), 80)
FROM sys.extended_properties WHERE class = 0 AND name = N'CONSTITUTION.md'
UNION ALL
SELECT scope = 'OBJECT',
       object_name = OBJECT_SCHEMA_NAME(major_id) + N'.' + OBJECT_NAME(major_id),
       property = name,
       value_preview = LEFT(CONVERT(nvarchar(max), value), 80)
FROM sys.extended_properties WHERE class = 1 AND name = N'AGENTS.md'
ORDER BY scope, object_name;
GO

PRINT 'Done. Connect SSMS Copilot to WideWorldImporters to pick up these instructions.';
PRINT 'Copilot runs under the login you connect with -- use a least-privilege login.';
GO

/* ---------------------------------------------------------------------------
   7) OPTIONAL (corner case): pin Copilot execution to a SPECIFIC identity.
   ---------------------------------------------------------------------------
   By default (section 4) Copilot runs under whoever is connected, and SQL Server
   permissions are the security boundary. The demo keeps that default visible and
   uses GHCP_DB_User only for the direct permission test. In a customer design,
   use a dedicated least-privilege connected or pinned identity.

   Only in the corner case where you want Copilot pinned to ONE fixed identity no
   matter who is connected (for example a shared, audited "AI investigator"
   account) do you add an agentExecuteAsUser value to the constitution front
   matter. SSMS then wraps every Copilot query in EXECUTE AS for that identity.

   Microsoft documents both a database user and SQL login as supported identity
   types. Some earlier SSMS builds or environments produced connection-context
   errors with WITHOUT LOGIN users, so test the exact SSMS build and
   authentication model before choosing one. The connected account also needs
   IMPERSONATE permission on the selected identity.

   To enable the pin, run something like this (uncomment and adjust):

   -- CREATE LOGIN GHCP_Login WITH PASSWORD = N'<strong-password>';
   -- CREATE USER  GHCP_Login FOR LOGIN GHCP_Login;
   -- GRANT SELECT ON SCHEMA::Demo        TO GHCP_Login;
   -- GRANT SELECT ON SCHEMA::Sales       TO GHCP_Login;
   -- GRANT SELECT ON SCHEMA::Warehouse   TO GHCP_Login;
   -- GRANT SELECT ON SCHEMA::Application TO GHCP_Login;
   -- GRANT EXECUTE ON SCHEMA::Demo       TO GHCP_Login;
   -- GRANT VIEW DATABASE STATE           TO GHCP_Login;
   -- GRANT IMPERSONATE ON USER::GHCP_Login TO [<your_connected_login_or_user>];
   --
   -- Then reinstall the constitution WITH the front matter (note the blank line
   -- before the closing --- , matching the documented format):
   --
   -- DECLARE @pinned nvarchar(4000) = N'---
   -- agentExecuteAsUser: GHCP_Login
   --
   -- ---
   -- <paste the same constitution body from section 4 here>';
   -- IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 0 AND name = N'CONSTITUTION.md')
   --     EXEC sys.sp_dropextendedproperty @name = N'CONSTITUTION.md';
   -- EXEC sys.sp_addextendedproperty @name = N'CONSTITUTION.md', @value = @pinned;
   --------------------------------------------------------------------------- */
GO
