/* =============================================================================
   02b-amplify-demo-data.sql

   Purpose : Populate Demo.LargeInvoiceFact with enough rows (default ~10 million)
             to make a query regression and its fix dramatic and measurable.
             Rows are projected from the real WideWorldImporters invoice tables,
             with each batch shifted back one year so invoice dates span many
             years. That date spread is what makes the date-filter query pattern
             (sargable range vs non-sargable YEAR()) behave so differently.
   Run as  : A login with INSERT on Demo.LargeInvoiceFact and SELECT on Sales.*.
   Safe    : Only inserts into Demo.LargeInvoiceFact. Reads Sales.* read-only.
   Idempotent : If the table already has >= @TargetRows rows it does nothing.
                To rebuild from scratch, TRUNCATE first (see commented line).

   TIP: This can take several minutes and will grow the transaction log. For a
        throwaway demo you may temporarily set the database to SIMPLE recovery.
   ============================================================================= */
SET NOCOUNT ON;
USE WideWorldImporters;
GO

-- To rebuild the fact table from empty, uncomment the next line:
-- TRUNCATE TABLE Demo.LargeInvoiceFact;

DECLARE @TargetRows bigint = 10000000;   -- <-- adjust for a larger/smaller demo

DECLARE @current   bigint = (SELECT COUNT_BIG(*) FROM Demo.LargeInvoiceFact);
DECLARE @batchSize bigint =
(
    SELECT COUNT_BIG(*)
    FROM Sales.Invoices       AS i
    JOIN Sales.InvoiceLines   AS il ON il.InvoiceID = i.InvoiceID
);

IF @batchSize = 0
BEGIN
    RAISERROR('Source tables Sales.Invoices/Sales.InvoiceLines are empty. Restore WideWorldImporters first.', 16, 1);
    RETURN;
END;

IF @current >= @TargetRows
BEGIN
    PRINT CONCAT('[SKIP] Demo.LargeInvoiceFact already has ', @current, ' rows (>= target ', @TargetRows, ').');
    RETURN;
END;

DECLARE @batch int = 0;
DECLARE @take  bigint;
DECLARE @msg   nvarchar(200);

PRINT CONCAT('[INFO] Amplifying from ', @current, ' to ~', @TargetRows, ' rows (batch size ~', @batchSize, ')...');

WHILE @current < @TargetRows
BEGIN
    SET @take = CASE WHEN (@TargetRows - @current) < @batchSize
                     THEN (@TargetRows - @current)
                     ELSE @batchSize END;

    INSERT INTO Demo.LargeInvoiceFact
        (InvoiceID, CustomerID, CityID, StockItemID, InvoiceDate,
         Quantity, UnitPrice, LineTotal, SalespersonPersonID)
    SELECT TOP (@take)
        i.InvoiceID,
        i.CustomerID,
        c.DeliveryCityID,
        il.StockItemID,
        DATEADD(YEAR, -@batch, CAST(i.InvoiceDate AS date)),   -- shift each batch back a year
        il.Quantity,
        il.UnitPrice,
        il.ExtendedPrice,
        i.SalespersonPersonID
    FROM Sales.Invoices     AS i
    JOIN Sales.InvoiceLines AS il ON il.InvoiceID = i.InvoiceID
    JOIN Sales.Customers    AS c  ON c.CustomerID = i.CustomerID;

    SET @batch  += 1;
    SET @current = (SELECT COUNT_BIG(*) FROM Demo.LargeInvoiceFact);

    SET @msg = CONCAT('[INFO] Batch ', @batch, ' done; row count = ', @current, '.');
    RAISERROR(@msg, 0, 1) WITH NOWAIT;   -- stream progress immediately
END;

DECLARE @distinctYears int =
    (SELECT COUNT(DISTINCT YEAR(InvoiceDate)) FROM Demo.LargeInvoiceFact);
PRINT CONCAT('[OK]  Demo.LargeInvoiceFact now has ', @current, ' rows across ',
             @distinctYears, ' distinct years.');
PRINT 'Next: 03-create-demo-procedures.sql';
GO
