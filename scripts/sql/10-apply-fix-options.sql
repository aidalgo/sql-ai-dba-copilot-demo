/* =============================================================================
   10-apply-fix-options.sql

   Purpose : A menu of remediation options for the regression, from the best
             (fix the code + index) to the more tactical (force a plan / apply a
             hint without a code change). Each section documents WHEN to use it,
             the RISK, how to VALIDATE, and how to ROLLBACK.

   RECOMMENDED DEFAULT FIX = Section A (sargable code) + Section B (recreate the
   index) + Section C (refresh stats). Sections D and E are shown as templates for
   when you cannot change the code immediately.

   Run as  : A login with ALTER on Demo.LargeInvoiceFact (B, C) and, for D/E,
             ALTER on the database / Query Store.
   Safe    : Sections B and C are idempotent and safe to run. Sections A, D, E are
             documented; D and E are commented templates you fill in.
   ============================================================================= */
SET NOCOUNT ON;
USE WideWorldImporters;
GO

/* ===========================================================================
   SECTION A -- Fix the query code (PRIMARY FIX)
   ---------------------------------------------------------------------------
   WHEN : Always prefer this. The regression's root cause is a non-sargable
          predicate ( YEAR(InvoiceDate) = @Year ). Replace it with a sargable
          half-open date range so an index seek is possible:

              -- BEFORE (non-sargable):
              WHERE YEAR(f.InvoiceDate) = @Year
              -- AFTER (sargable):
              WHERE f.InvoiceDate >= DATEFROMPARTS(@Year, 1, 1)
                AND f.InvoiceDate <  DATEFROMPARTS(@Year + 1, 1, 1)

          In this demo the corrected logic already lives in the *_Fixed
          procedures (see 03-create-demo-procedures.sql), and the fixed workload
          (11-run-fixed-workload.sql) calls them. In a real system you would ALTER
          the offending procedure/query to the sargable form and redeploy.
   RISK : Minimal -- same results, better plan. Re-test result parity.
   VALIDATE : Re-run the workload and 12-query-store-after-fix-report.sql.
   ROLLBACK : Revert the code change (redeploy the previous version).
   =========================================================================== */
PRINT '[A] Primary fix is the sargable code in Demo.*_Fixed (used by 11-run-fixed-workload.sql). No action needed here.';
GO

/* ===========================================================================
   SECTION B -- Recreate the supporting index  (RUN THIS)
   ---------------------------------------------------------------------------
   WHEN : The cleanup migration dropped IX_Demo_LargeInvoiceFact_InvoiceDate.
          Recreating it lets the sargable predicate seek instead of scan.
   RISK : Low. Index creation uses resources; on huge tables consider
          ONLINE = ON (Enterprise) and a maintenance window.
   VALIDATE : sys.indexes shows the index; plans switch to Index Seek.
   ROLLBACK : DROP INDEX (see Rollback section at the bottom).
   =========================================================================== */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_Demo_LargeInvoiceFact_InvoiceDate'
                 AND object_id = OBJECT_ID(N'Demo.LargeInvoiceFact'))
BEGIN
    PRINT '[B] Recreating IX_Demo_LargeInvoiceFact_InvoiceDate...';
    CREATE NONCLUSTERED INDEX IX_Demo_LargeInvoiceFact_InvoiceDate
        ON Demo.LargeInvoiceFact (InvoiceDate)
        INCLUDE (CustomerID, CityID, Quantity, LineTotal)
        WITH (DATA_COMPRESSION = PAGE, ONLINE = OFF);
    PRINT '[B] Index recreated.';
END
ELSE
    PRINT '[B] IX_Demo_LargeInvoiceFact_InvoiceDate already present.';
GO

/* ===========================================================================
   SECTION C -- Refresh statistics  (RUN THIS)
   ---------------------------------------------------------------------------
   WHEN : After large data changes or index changes, stale stats can cause poor
          estimates. Refresh so the optimizer costs the new index correctly.
   RISK : FULLSCAN reads the whole table; on huge tables use sampled stats or a
          maintenance window.
   VALIDATE : STATS_DATE() shows a recent update; estimates improve.
   ROLLBACK : Not applicable (stats refresh is not harmful).
   =========================================================================== */
PRINT '[C] Updating statistics on Demo.LargeInvoiceFact...';
UPDATE STATISTICS Demo.LargeInvoiceFact WITH FULLSCAN;
PRINT '[C] Statistics updated.';
GO

/* ===========================================================================
   SECTION D -- Force a known-good plan via Query Store  (TEMPLATE)
   ---------------------------------------------------------------------------
   WHEN : You need to stabilize a query RIGHT NOW and cannot change code, and
          Query Store still has a good (fast) plan for it. Forcing pins that plan.
   RISK : A forced plan can become suboptimal as data shifts; revisit it. Forcing
          is a stopgap, not a substitute for fixing the query/index.
   VALIDATE : sys.query_store_plan.is_forced_plan = 1; runtime improves.
   ROLLBACK : sp_query_store_unforce_plan (see Rollback section).

   Steps: find the fast plan_id for your query_id, then force it.
   ---------------------------------------------------------------------------
   -- 1) Find candidate plans (fastest first) for a query_id from a report:
   --    DECLARE @query_id bigint = <from 09/12 report>;
   --    SELECT p.plan_id, p.is_forced_plan,
   --           avg_ms = CONVERT(decimal(18,2),
   --                    SUM(rs.avg_duration*rs.count_executions)/NULLIF(SUM(rs.count_executions),0)/1000.0)
   --    FROM sys.query_store_plan p
   --    JOIN sys.query_store_runtime_stats rs ON rs.plan_id = p.plan_id
   --    WHERE p.query_id = @query_id
   --    GROUP BY p.plan_id, p.is_forced_plan
   --    ORDER BY avg_ms ASC;
   --
   -- 2) Force the chosen fast plan:
   --    EXEC sys.sp_query_store_force_plan @query_id = <query_id>, @plan_id = <fast_plan_id>;
   =========================================================================== */
PRINT '[D] Plan forcing is a commented template -- fill in query_id/plan_id from a report.';
GO

/* ===========================================================================
   SECTION E -- Apply a query hint without code change (Query Store hints) (TEMPLATE)
   ---------------------------------------------------------------------------
   WHEN : You cannot change the code, plan forcing is not enough, and a targeted
          hint would help (e.g. RECOMPILE for parameter-sensitive plans). Query
          Store hints attach a hint to a query_id with no application change.
   RISK : Hints override the optimizer; document and review. Wrong hints can hurt.
   VALIDATE : sys.query_store_query_hints shows the hint; runtime improves.
   ROLLBACK : sys.sp_query_store_clear_hints (see Rollback section).
   ---------------------------------------------------------------------------
   -- Example: force a recompile each execution for a parameter-sensitive query:
   --    EXEC sys.sp_query_store_set_hints
   --         @query_id = <query_id>,
   --         @query_hints = N'OPTION(RECOMPILE)';
   --
   -- Example: cap the memory grant:
   --    EXEC sys.sp_query_store_set_hints
   --         @query_id = <query_id>,
   --         @query_hints = N'OPTION(MIN_GRANT_PERCENT = 5, MAX_GRANT_PERCENT = 25)';
   =========================================================================== */
PRINT '[E] Query Store hints are a commented template -- fill in query_id/hint text.';
GO

PRINT '====================================================================';
PRINT ' Fix applied (Sections B + C). Now run 11-run-fixed-workload.sql, then';
PRINT ' 12-query-store-after-fix-report.sql to prove the improvement.';
PRINT '====================================================================';
GO

/* ===========================================================================
   ROLLBACK (commented on purpose -- run a line only if you want to undo)
   ---------------------------------------------------------------------------
   -- Undo Section B (drop the index again):
   -- DROP INDEX IF EXISTS IX_Demo_LargeInvoiceFact_InvoiceDate ON Demo.LargeInvoiceFact;
   --
   -- Undo Section D (unforce a plan):
   -- EXEC sys.sp_query_store_unforce_plan @query_id = <query_id>, @plan_id = <plan_id>;
   --
   -- Undo Section E (clear hints for a query):
   -- EXEC sys.sp_query_store_clear_hints @query_id = <query_id>;
   --
   -- "Undo" Section A: redeploy the previous (non-sargable) procedure version.
   =========================================================================== */
