/* =============================================================================
   07-run-regressed-workload.sql

   Purpose : Drive the regressed workload so Query Store records the slow plans.
             Calls the _Regressed (non-sargable) procedures, and by now the date
             index has been dropped (06), so every call scans ~10M rows.
   Run as  : A login with EXECUTE on the Demo procedures.
   Safe    : Reads Demo.LargeInvoiceFact; writes only to Demo.WorkloadLog.

   NOTE: This is intentionally SLOW. Each iteration scans the full fact table.
         Lower @Iterations if you want a shorter demo; even a few iterations are
         enough for Query Store to flag the regression.
   ============================================================================= */
SET NOCOUNT ON;
USE WideWorldImporters;
GO

DECLARE @Iterations int = 15;            -- intentionally fewer: each call is expensive
DECLARE @RunLabel   nvarchar(100) = N'regressed';

INSERT Demo.WorkloadLog (RunLabel, Phase, Iterations, Notes)
VALUES (@RunLabel, N'run', @Iterations,
        N'Non-sargable YEAR() procs + IX_Demo_LargeInvoiceFact_InvoiceDate dropped (expected: full scans, high CPU/reads).');
DECLARE @logId int = SCOPE_IDENTITY();
DECLARE @startedAt datetime2(3) = (SELECT StartedAt FROM Demo.WorkloadLog WHERE WorkloadLogID = @logId);
RAISERROR('--- REGRESSED workload started. WorkloadLogID=%d (this will be slow) ---', 0, 1, @logId) WITH NOWAIT;

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
    INSERT INTO @sumSink EXEC Demo.usp_GetCustomerInvoiceSummary_Regressed @CustomerID = @cust, @Year = @yr;
    INSERT INTO @regSink EXEC Demo.usp_GetRegionalSalesByYear_Regressed    @Year = @yr;

    SET @i += 1;
    RAISERROR('   regressed iteration %d of %d done', 0, 1, @i, @Iterations) WITH NOWAIT;
END;

UPDATE Demo.WorkloadLog SET EndedAt = SYSUTCDATETIME() WHERE WorkloadLogID = @logId;
DECLARE @endedAt datetime2(3) = (SELECT EndedAt FROM Demo.WorkloadLog WHERE WorkloadLogID = @logId);

PRINT '====================== REGRESSED COMPLETE ======================';
PRINT CONCAT(' WorkloadLogID : ', @logId);
PRINT CONCAT(' Window (UTC)  : ', CONVERT(varchar(30), @startedAt, 126), '  ..  ', CONVERT(varchar(30), @endedAt, 126));
PRINT ' Next          : 09-query-store-regression-report.sql to see the regression in Query Store';
PRINT '================================================================';
GO
