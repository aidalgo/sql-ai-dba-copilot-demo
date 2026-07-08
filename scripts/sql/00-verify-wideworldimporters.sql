/* =============================================================================
   00-verify-wideworldimporters.sql

   Purpose : Confirm the WideWorldImporters restore succeeded and the tables the
             demo depends on are present and populated.
   Run as  : Any login with VIEW DEFINITION / SELECT on WideWorldImporters.
   Safe    : Read-only. Makes no changes.
   ============================================================================= */
SET NOCOUNT ON;
USE WideWorldImporters;
GO

PRINT '== Database properties ==';
SELECT
    database_name        = DB_NAME(),
    compatibility_level  = compatibility_level,
    recovery_model       = CONVERT(varchar(20), DATABASEPROPERTYEX(DB_NAME(), 'Recovery')),
    state                = CONVERT(varchar(20), DATABASEPROPERTYEX(DB_NAME(), 'Status'))
FROM sys.databases
WHERE name = DB_NAME();
GO

PRINT '== Key source tables and row counts ==';
/* These are the tables the demo reads from to build the amplified fact table.
   If any row count is 0 (or the table is missing) the restore did not complete. */
SELECT
    [schema]   = s.name,
    [table]    = t.name,
    [rows]     = SUM(p.rows)
FROM sys.tables t
JOIN sys.schemas s        ON s.schema_id = t.schema_id
JOIN sys.partitions p     ON p.object_id = t.object_id AND p.index_id IN (0, 1)
WHERE (s.name = N'Sales'       AND t.name IN (N'Invoices', N'InvoiceLines', N'Customers'))
   OR (s.name = N'Warehouse'   AND t.name IN (N'StockItems'))
   OR (s.name = N'Application' AND t.name IN (N'People', N'Cities'))
GROUP BY s.name, t.name
ORDER BY s.name, t.name;
GO

/* Quick pass/fail summary the demo operator can eyeball. */
DECLARE @invoices bigint = (SELECT COUNT(*) FROM Sales.Invoices);
DECLARE @lines    bigint = (SELECT COUNT(*) FROM Sales.InvoiceLines);
IF @invoices > 0 AND @lines > 0
    PRINT CONCAT('[OK]  WideWorldImporters looks good. Sales.Invoices=', @invoices, ', Sales.InvoiceLines=', @lines, '.');
ELSE
    PRINT '[FAIL] Expected source tables are empty. Re-check the restore.';
GO
