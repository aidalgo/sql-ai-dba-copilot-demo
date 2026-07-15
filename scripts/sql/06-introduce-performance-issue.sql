/* =============================================================================
   06-introduce-performance-issue.sql

   Purpose : Simulate the "change that caused the regression". We DROP the
             supporting date index. Combined with the _Regressed (non-sargable)
             procedures, the demo queries now scan all ~10M rows on every call.

   REGRESSION MECHANISM:
     "A recent release did two unfortunate things at once:
        1. A developer 'optimized' a report query and accidentally changed a
           sargable date range (InvoiceDate >= @start AND < @end) into a
           non-sargable one (YEAR(InvoiceDate) = @Year).
        2. A cleanup migration dropped what looked like an 'unused' index
           (IX_Demo_LargeInvoiceFact_InvoiceDate).
      Individually each is bad; together they turn a millisecond seek into a
      multi-second full scan. Query Store recorded the before and after, so we
      can prove exactly what regressed and by how much."

   Run as  : A login with ALTER on Demo.LargeInvoiceFact.
   Safe    : Only drops a demo index. No WideWorldImporters objects are touched.
   Reversible : 10-apply-fix-options.sql (Section B) recreates this index.
   ============================================================================= */
SET NOCOUNT ON;
USE WideWorldImporters;
GO

IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = N'IX_Demo_LargeInvoiceFact_InvoiceDate'
             AND object_id = OBJECT_ID(N'Demo.LargeInvoiceFact'))
BEGIN
    PRINT '[INFO] Dropping IX_Demo_LargeInvoiceFact_InvoiceDate to amplify the regression...';
    DROP INDEX IX_Demo_LargeInvoiceFact_InvoiceDate ON Demo.LargeInvoiceFact;
    PRINT '[OK]  Index dropped. The date-filter queries will now scan the whole table.';
END
ELSE
    PRINT '[INFO] IX_Demo_LargeInvoiceFact_InvoiceDate is already absent (regression already in place).';
GO

PRINT 'Next: 07-run-regressed-workload.sql to capture the slow plans in Query Store.';
GO
