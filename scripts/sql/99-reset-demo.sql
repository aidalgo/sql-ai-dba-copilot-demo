/* =============================================================================
   99-reset-demo.sql

   Purpose : Remove everything this demo created so it can be run again from a
             clean state — WITHOUT re-restoring WideWorldImporters.
             Drops, in dependency-safe order:
               1. CONSTITUTION.md (database) + AGENTS.md (object) extended properties
               2. The 6 Demo stored procedures
               3. Demo.WorkloadLog and Demo.LargeInvoiceFact (their IX_Demo_* indexes
                  drop with the table)
               4. The GHCP_DB_User database user
               5. The Demo schema

   Leaves intact : ALL native WideWorldImporters objects (Sales/Warehouse/
                   Application/...). This script touches only demo-owned objects.
   Run as  : db_owner (or a login with DROP rights on the demo objects).
   Idempotent : Safe to re-run; every drop is guarded by an existence check.

   NOTE: Query Store itself (enabled by 01-enable-query-store.sql) is left ON and
         its data is kept. An optional CLEAR is provided (commented) at the end.
   ============================================================================= */
SET NOCOUNT ON;
USE WideWorldImporters;
GO

/* ---------------------------------------------------------------------------
   1a) Drop all object-level AGENTS.md extended properties (table + procedures).
       Generic so it works regardless of which objects still exist.
   --------------------------------------------------------------------------- */
DECLARE @schema sysname, @obj sysname, @l1type varchar(128);
DECLARE ep_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT OBJECT_SCHEMA_NAME(ep.major_id),
           OBJECT_NAME(ep.major_id),
           CASE o.type WHEN N'U' THEN 'TABLE' WHEN N'P' THEN 'PROCEDURE'
                       WHEN N'V' THEN 'VIEW'  WHEN N'FN' THEN 'FUNCTION'
                       WHEN N'IF' THEN 'FUNCTION' WHEN N'TF' THEN 'FUNCTION' END
    FROM sys.extended_properties ep
    JOIN sys.objects o ON o.object_id = ep.major_id
    WHERE ep.class = 1 AND ep.name = N'AGENTS.md'
      AND OBJECT_SCHEMA_NAME(ep.major_id) = N'Demo';

OPEN ep_cur;
FETCH NEXT FROM ep_cur INTO @schema, @obj, @l1type;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF @l1type IS NOT NULL
        EXEC sys.sp_dropextendedproperty @name = N'AGENTS.md',
             @level0type = N'SCHEMA', @level0name = @schema,
             @level1type = @l1type,  @level1name = @obj;
    FETCH NEXT FROM ep_cur INTO @schema, @obj, @l1type;
END
CLOSE ep_cur;
DEALLOCATE ep_cur;
PRINT '[OK]  Removed object-level AGENTS.md extended properties (if any).';
GO

/* 1b) Drop the database-level CONSTITUTION.md extended property. */
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 0 AND name = N'CONSTITUTION.md')
BEGIN
    EXEC sys.sp_dropextendedproperty @name = N'CONSTITUTION.md';
    PRINT '[OK]  Removed database-level CONSTITUTION.md extended property.';
END
ELSE
    PRINT '[INFO] CONSTITUTION.md extended property not present.';
GO

/* ---------------------------------------------------------------------------
   2) Drop the demo stored procedures.
   --------------------------------------------------------------------------- */
DROP PROCEDURE IF EXISTS Demo.usp_GetCustomerInvoiceSummary_Baseline;
DROP PROCEDURE IF EXISTS Demo.usp_GetCustomerInvoiceSummary_Regressed;
DROP PROCEDURE IF EXISTS Demo.usp_GetCustomerInvoiceSummary_Fixed;
DROP PROCEDURE IF EXISTS Demo.usp_GetRegionalSalesByYear_Baseline;
DROP PROCEDURE IF EXISTS Demo.usp_GetRegionalSalesByYear_Regressed;
DROP PROCEDURE IF EXISTS Demo.usp_GetRegionalSalesByYear_Fixed;
PRINT '[OK]  Dropped Demo stored procedures (if present).';
GO

/* ---------------------------------------------------------------------------
   3) Drop the demo tables. The IX_Demo_* indexes are dropped with the table.
   --------------------------------------------------------------------------- */
DROP TABLE IF EXISTS Demo.WorkloadLog;
DROP TABLE IF EXISTS Demo.LargeInvoiceFact;
PRINT '[OK]  Dropped Demo tables and their IX_Demo_* indexes (if present).';
GO

/* ---------------------------------------------------------------------------
   4) Drop the low-privilege investigation user (its grants drop with it).
   --------------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'GHCP_DB_User' AND type = N'S')
BEGIN
    DROP USER GHCP_DB_User;
    PRINT '[OK]  Dropped database user GHCP_DB_User.';
END
ELSE
    PRINT '[INFO] GHCP_DB_User not present.';
GO

/* ---------------------------------------------------------------------------
   5) Drop the now-empty Demo schema.
   --------------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'Demo')
BEGIN
    DROP SCHEMA Demo;
    PRINT '[OK]  Dropped schema Demo.';
END
ELSE
    PRINT '[INFO] Schema Demo not present.';
GO

PRINT 'Reset complete. WideWorldImporters native objects were left intact.';
PRINT 'Re-run 02 -> 04 (and 02b for Enhanced mode) and 15 to rebuild the demo.';
GO

/* ---------------------------------------------------------------------------
   OPTIONAL: also purge the Query Store history captured during the demo.
   Leave commented unless you want a completely clean before/after next time.
   --------------------------------------------------------------------------- */
-- ALTER DATABASE WideWorldImporters SET QUERY_STORE CLEAR;
-- PRINT '[OK]  Cleared Query Store data.';
GO
