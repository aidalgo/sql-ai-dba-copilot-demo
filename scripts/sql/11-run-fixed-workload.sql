/* =============================================================================
   11-run-fixed-workload.sql

   Purpose : Drive the workload again AFTER the fix has been applied
             (10-apply-fix-options.sql recreated the index and the _Fixed
             sargable procedures are used). Query Store records fast plans again,
             giving a clean before/after/after story.
   Run as  : A login with EXECUTE on the Demo procedures.
   Safe    : Reads Demo.LargeInvoiceFact; writes only to Demo.WorkloadLog.

   PREREQUISITE: run 10-apply-fix-options.sql first so the date index exists
                 again. The _Fixed procedures are sargable regardless.
   ============================================================================= */
SET NOCOUNT ON;
USE WideWorldImporters;
GO

IF NOT EXISTS (SELECT 1 FROM Demo.LargeInvoiceFact)
BEGIN
    THROW 51000, 'Demo.LargeInvoiceFact is empty. Run 02b-amplify-demo-data.sql before the workload.', 1;
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_Demo_LargeInvoiceFact_InvoiceDate'
                 AND object_id = OBJECT_ID(N'Demo.LargeInvoiceFact'))
    RAISERROR('NOTE: IX_Demo_LargeInvoiceFact_InvoiceDate is missing. Run 10-apply-fix-options.sql (Section B) for the full speed-up.', 0, 1) WITH NOWAIT;
GO

DECLARE @Iterations int = 25;
DECLARE @RunLabel   nvarchar(100) = N'fixed';

INSERT Demo.WorkloadLog (RunLabel, Phase, Iterations, Notes)
VALUES (@RunLabel, N'run', @Iterations,
        N'Sargable _Fixed procs + IX_Demo_LargeInvoiceFact_InvoiceDate recreated (expected: fast index seeks again).');
DECLARE @logId int = SCOPE_IDENTITY();
DECLARE @startedAt datetime2(3) = (SELECT StartedAt FROM Demo.WorkloadLog WHERE WorkloadLogID = @logId);
RAISERROR('--- FIXED workload started. WorkloadLogID=%d ---', 0, 1, @logId) WITH NOWAIT;

DECLARE @years TABLE (rn int IDENTITY(1,1), y int);
INSERT @years (y) SELECT DISTINCT YEAR(InvoiceDate) FROM Demo.LargeInvoiceFact;
DECLARE @yc int = (SELECT COUNT(*) FROM @years);

DECLARE @custs TABLE (rn int IDENTITY(1,1), c int);
INSERT @custs (c) SELECT TOP (50) CustomerID
                  FROM (SELECT DISTINCT CustomerID FROM Demo.LargeInvoiceFact) x
                  ORDER BY CustomerID;
DECLARE @cc int = (SELECT COUNT(*) FROM @custs);

DECLARE @sumSink TABLE (CustomerID int, InvoiceCount bigint, TotalQuantity bigint, TotalSales decimal(38,2));
DECLARE @regSink TABLE (CityID int, InvoiceCount bigint, TotalSales decimal(38,2));

DECLARE @i int = 0, @yr int, @cust int;
WHILE @i < @Iterations
BEGIN
    SET @yr   = (SELECT y FROM @years WHERE rn = (@i % @yc) + 1);
    SET @cust = (SELECT c FROM @custs WHERE rn = (@i % @cc) + 1);

    DELETE FROM @sumSink;
    DELETE FROM @regSink;
    INSERT INTO @sumSink EXEC Demo.usp_GetCustomerInvoiceSummary_Fixed @CustomerID = @cust, @Year = @yr;
    INSERT INTO @regSink EXEC Demo.usp_GetRegionalSalesByYear_Fixed    @Year = @yr;

    SET @i += 1;
END;

UPDATE Demo.WorkloadLog SET EndedAt = SYSUTCDATETIME() WHERE WorkloadLogID = @logId;
DECLARE @endedAt datetime2(3) = (SELECT EndedAt FROM Demo.WorkloadLog WHERE WorkloadLogID = @logId);

PRINT '======================== FIXED COMPLETE ========================';
PRINT CONCAT(' WorkloadLogID : ', @logId);
PRINT CONCAT(' Window (UTC)  : ', CONVERT(varchar(30), @startedAt, 126), '  ..  ', CONVERT(varchar(30), @endedAt, 126));
PRINT ' Next          : 12-query-store-after-fix-report.sql to prove the improvement';
PRINT '===============================================================';
GO
