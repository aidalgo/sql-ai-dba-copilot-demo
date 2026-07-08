/* =============================================================================
   03-create-demo-procedures.sql

   Purpose : Create the stored procedures the demo workloads call. For each
             business query there are three variants:
               _Baseline : well-written, SARGABLE date predicate (can seek).
               _Regressed: same result, but a NON-SARGABLE predicate (forces a
                           scan) -- this is the "bad change a developer shipped".
               _Fixed    : the corrected, sargable version applied during the fix.

   WHY SARGABILITY MATTERS (the whole point of the demo):
     SARGable  : WHERE InvoiceDate >= @start AND InvoiceDate < @end
                 -> the predicate is on the bare column, so SQL Server can use an
                    index seek on InvoiceDate and touch only the matching rows.
     NON-sarg. : WHERE YEAR(InvoiceDate) = @Year
                 -> wrapping the column in a function means the index can't be
                    seeked; SQL Server scans every row and computes YEAR() first.

   Run as  : A login with CREATE PROCEDURE on WideWorldImporters.
   Safe    : Creates/updates procedures in the Demo schema only.
   Idempotent : Uses CREATE OR ALTER.
   ============================================================================= */
SET NOCOUNT ON;
USE WideWorldImporters;
GO

/* ---------------------------------------------------------------------------
   Customer invoice summary for one customer in one year.
   --------------------------------------------------------------------------- */

-- BASELINE: sargable date range -> index seek friendly.
CREATE OR ALTER PROCEDURE Demo.usp_GetCustomerInvoiceSummary_Baseline
    @CustomerID int,
    @Year       int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @start date = DATEFROMPARTS(@Year, 1, 1);
    DECLARE @end   date = DATEFROMPARTS(@Year + 1, 1, 1);

    SELECT
        f.CustomerID,
        InvoiceCount = COUNT_BIG(*),
        TotalQuantity = SUM(CONVERT(bigint, f.Quantity)),
        TotalSales    = SUM(f.LineTotal)
    FROM Demo.LargeInvoiceFact AS f
    WHERE f.CustomerID = @CustomerID
      AND f.InvoiceDate >= @start
      AND f.InvoiceDate <  @end          -- SARGABLE: bare column compared to constants
    GROUP BY f.CustomerID;
END;
GO

-- REGRESSED: function on the column -> non-sargable -> scan.
CREATE OR ALTER PROCEDURE Demo.usp_GetCustomerInvoiceSummary_Regressed
    @CustomerID int,
    @Year       int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        f.CustomerID,
        InvoiceCount = COUNT_BIG(*),
        TotalQuantity = SUM(CONVERT(bigint, f.Quantity)),
        TotalSales    = SUM(f.LineTotal)
    FROM Demo.LargeInvoiceFact AS f
    WHERE f.CustomerID = @CustomerID
      AND YEAR(f.InvoiceDate) = @Year     -- NON-SARGABLE: YEAR() wraps the column
    GROUP BY f.CustomerID;
END;
GO

-- FIXED: corrected back to the sargable range form.
CREATE OR ALTER PROCEDURE Demo.usp_GetCustomerInvoiceSummary_Fixed
    @CustomerID int,
    @Year       int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @start date = DATEFROMPARTS(@Year, 1, 1);
    DECLARE @end   date = DATEFROMPARTS(@Year + 1, 1, 1);

    SELECT
        f.CustomerID,
        InvoiceCount = COUNT_BIG(*),
        TotalQuantity = SUM(CONVERT(bigint, f.Quantity)),
        TotalSales    = SUM(f.LineTotal)
    FROM Demo.LargeInvoiceFact AS f
    WHERE f.CustomerID = @CustomerID
      AND f.InvoiceDate >= @start
      AND f.InvoiceDate <  @end;          -- SARGABLE again
END;
GO

/* ---------------------------------------------------------------------------
   Regional sales aggregated by city for one year.
   --------------------------------------------------------------------------- */

-- BASELINE: sargable date range.
CREATE OR ALTER PROCEDURE Demo.usp_GetRegionalSalesByYear_Baseline
    @Year int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @start date = DATEFROMPARTS(@Year, 1, 1);
    DECLARE @end   date = DATEFROMPARTS(@Year + 1, 1, 1);

    SELECT TOP (100)
        f.CityID,
        InvoiceCount = COUNT_BIG(*),
        TotalSales   = SUM(f.LineTotal)
    FROM Demo.LargeInvoiceFact AS f
    WHERE f.InvoiceDate >= @start
      AND f.InvoiceDate <  @end           -- SARGABLE
    GROUP BY f.CityID
    ORDER BY TotalSales DESC;
END;
GO

-- REGRESSED: non-sargable predicate (YEAR()).  An equally common offender is
-- CONVERT(date, InvoiceDate) BETWEEN ... ; either way the column is wrapped.
CREATE OR ALTER PROCEDURE Demo.usp_GetRegionalSalesByYear_Regressed
    @Year int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (100)
        f.CityID,
        InvoiceCount = COUNT_BIG(*),
        TotalSales   = SUM(f.LineTotal)
    FROM Demo.LargeInvoiceFact AS f
    WHERE YEAR(f.InvoiceDate) = @Year      -- NON-SARGABLE
    GROUP BY f.CityID
    ORDER BY TotalSales DESC;
END;
GO

-- FIXED: corrected back to the sargable range form.
CREATE OR ALTER PROCEDURE Demo.usp_GetRegionalSalesByYear_Fixed
    @Year int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @start date = DATEFROMPARTS(@Year, 1, 1);
    DECLARE @end   date = DATEFROMPARTS(@Year + 1, 1, 1);

    SELECT TOP (100)
        f.CityID,
        InvoiceCount = COUNT_BIG(*),
        TotalSales   = SUM(f.LineTotal)
    FROM Demo.LargeInvoiceFact AS f
    WHERE f.InvoiceDate >= @start
      AND f.InvoiceDate <  @end           -- SARGABLE again
    GROUP BY f.CityID
    ORDER BY TotalSales DESC;
END;
GO

PRINT '[OK]  Created/updated the 6 demo procedures.';
PRINT 'Next: 04-create-baseline-indexes.sql';
GO
