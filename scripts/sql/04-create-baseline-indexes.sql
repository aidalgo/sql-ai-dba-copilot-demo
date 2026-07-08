/* =============================================================================
   04-create-baseline-indexes.sql

   Purpose : Create the "healthy" baseline indexes. With these in place AND the
             sargable (baseline) procedures, the demo queries do efficient index
             seeks. The regression script (06) later DROPS the date index to make
             the bad query pattern catastrophic; the fix recreates it.
   Run as  : A login with ALTER on Demo.LargeInvoiceFact.
   Safe    : Only creates indexes on Demo.LargeInvoiceFact.
   Idempotent : Creates each index only if it does not already exist.
   ============================================================================= */
SET NOCOUNT ON;
USE WideWorldImporters;
GO

/* Date index that makes the sargable range predicate a seek.
   INCLUDEs the measures/keys the demo queries read, so the queries are covered
   (no key lookups back to the clustered index). */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_Demo_LargeInvoiceFact_InvoiceDate'
                 AND object_id = OBJECT_ID(N'Demo.LargeInvoiceFact'))
BEGIN
    PRINT '[INFO] Creating IX_Demo_LargeInvoiceFact_InvoiceDate...';
    CREATE NONCLUSTERED INDEX IX_Demo_LargeInvoiceFact_InvoiceDate
        ON Demo.LargeInvoiceFact (InvoiceDate)
        INCLUDE (CustomerID, CityID, Quantity, LineTotal)
        WITH (DATA_COMPRESSION = PAGE, ONLINE = OFF);
    PRINT '[OK]  Created IX_Demo_LargeInvoiceFact_InvoiceDate.';
END
ELSE
    PRINT '[INFO] IX_Demo_LargeInvoiceFact_InvoiceDate already exists.';
GO

/* Customer index supporting per-customer lookups. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_Demo_LargeInvoiceFact_CustomerID'
                 AND object_id = OBJECT_ID(N'Demo.LargeInvoiceFact'))
BEGIN
    PRINT '[INFO] Creating IX_Demo_LargeInvoiceFact_CustomerID...';
    CREATE NONCLUSTERED INDEX IX_Demo_LargeInvoiceFact_CustomerID
        ON Demo.LargeInvoiceFact (CustomerID, InvoiceDate)
        INCLUDE (Quantity, LineTotal)
        WITH (DATA_COMPRESSION = PAGE, ONLINE = OFF);
    PRINT '[OK]  Created IX_Demo_LargeInvoiceFact_CustomerID.';
END
ELSE
    PRINT '[INFO] IX_Demo_LargeInvoiceFact_CustomerID already exists.';
GO

/* Make sure statistics are fresh after the big load. */
UPDATE STATISTICS Demo.LargeInvoiceFact WITH FULLSCAN;
PRINT '[OK]  Baseline indexes ready and statistics updated.';
PRINT 'Next: 05-run-baseline-workload.sql (capture a healthy baseline in Query Store)';
GO
