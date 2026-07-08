/* =============================================================================
   05-run-baseline-workload.sql

   Purpose : Drive a healthy baseline workload so Query Store records "good" plans
             and runtime stats. Calls the _Baseline (sargable) procedures with the
             date index in place. Records the run's UTC time window in
             Demo.WorkloadLog so the report scripts can isolate this exact run.
   Run as  : A login with EXECUTE on the Demo procedures.
   Safe    : Reads Demo.LargeInvoiceFact; writes only to Demo.WorkloadLog.
   ============================================================================= */
SET NOCOUNT ON;
USE WideWorldImporters;
GO

DECLARE @Iterations int = 25;            -- <-- raise for more Query Store samples
DECLARE @RunLabel   nvarchar(100) = N'baseline';

/* Open a workload-log row and remember the start time. */
INSERT Demo.WorkloadLog (RunLabel, Phase, Iterations, Notes)
VALUES (@RunLabel, N'run', @Iterations,
        N'Sargable procs + IX_Demo_LargeInvoiceFact_InvoiceDate present (expected: fast index seeks).');
DECLARE @logId int = SCOPE_IDENTITY();
DECLARE @startedAt datetime2(3) = (SELECT StartedAt FROM Demo.WorkloadLog WHERE WorkloadLogID = @logId);
RAISERROR('--- BASELINE workload started. WorkloadLogID=%d ---', 0, 1, @logId) WITH NOWAIT;

/* Build a small set of valid parameter values from the data itself. */
DECLARE @years TABLE (rn int IDENTITY(1,1), y int);
INSERT @years (y) SELECT DISTINCT YEAR(InvoiceDate) FROM Demo.LargeInvoiceFact;
DECLARE @yc int = (SELECT COUNT(*) FROM @years);

DECLARE @custs TABLE (rn int IDENTITY(1,1), c int);
INSERT @custs (c) SELECT TOP (50) CustomerID
                  FROM (SELECT DISTINCT CustomerID FROM Demo.LargeInvoiceFact) x
                  ORDER BY CustomerID;
DECLARE @cc int = (SELECT COUNT(*) FROM @custs);

/* Sinks so procedure result sets are captured (executed) but not printed. */
DECLARE @sumSink TABLE (CustomerID int, InvoiceCount bigint, TotalQuantity bigint, TotalSales decimal(38,2));
DECLARE @regSink TABLE (CityID int, InvoiceCount bigint, TotalSales decimal(38,2));

DECLARE @i int = 0, @yr int, @cust int;
WHILE @i < @Iterations
BEGIN
    SET @yr   = (SELECT y FROM @years WHERE rn = (@i % @yc) + 1);
    SET @cust = (SELECT c FROM @custs WHERE rn = (@i % @cc) + 1);

    DELETE FROM @sumSink;
    DELETE FROM @regSink;
    INSERT INTO @sumSink EXEC Demo.usp_GetCustomerInvoiceSummary_Baseline @CustomerID = @cust, @Year = @yr;
    INSERT INTO @regSink EXEC Demo.usp_GetRegionalSalesByYear_Baseline    @Year = @yr;

    SET @i += 1;
END;

UPDATE Demo.WorkloadLog SET EndedAt = SYSUTCDATETIME() WHERE WorkloadLogID = @logId;
DECLARE @endedAt datetime2(3) = (SELECT EndedAt FROM Demo.WorkloadLog WHERE WorkloadLogID = @logId);

PRINT '====================== BASELINE COMPLETE ======================';
PRINT CONCAT(' WorkloadLogID : ', @logId);
PRINT CONCAT(' Window (UTC)  : ', CONVERT(varchar(30), @startedAt, 126), '  ..  ', CONVERT(varchar(30), @endedAt, 126));
PRINT ' Next          : 08-query-store-baseline-report.sql, then 06-introduce-performance-issue.sql';
PRINT '===============================================================';
GO
