/* =============================================================================
   02-create-demo-schema.sql

   Purpose : Create the isolated `Demo` schema and the two objects the demo owns:
               - Demo.LargeInvoiceFact : a denormalized, amplified fact table that
                 is big enough to show a dramatic query regression and fix.
               - Demo.WorkloadLog      : records each workload run's time window so
                 the Query Store reports can filter to the exact before/after runs.
   Run as  : A login with CREATE SCHEMA / CREATE TABLE on WideWorldImporters.
   Safe    : Only creates objects under the `Demo` schema. Does NOT touch any
             WideWorldImporters (Sales/Warehouse/Application) tables.
   Idempotent : Safe to re-run; creates objects only if they do not exist.
   ============================================================================= */
SET NOCOUNT ON;
USE WideWorldImporters;
GO

/* 1) Dedicated schema so every demo object is easy to find and to clean up. */
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'Demo')
BEGIN
    EXEC('CREATE SCHEMA Demo AUTHORIZATION dbo;');
    PRINT '[OK]  Created schema Demo.';
END
ELSE
    PRINT '[INFO] Schema Demo already exists.';
GO

/* 2) The amplified fact table.
      Denormalized on purpose: a single wide table makes the date-range query
      pattern (and the sargable vs non-sargable contrast) easy to demonstrate. */
IF OBJECT_ID(N'Demo.LargeInvoiceFact', N'U') IS NULL
BEGIN
    CREATE TABLE Demo.LargeInvoiceFact
    (
        InvoiceFactID        bigint        IDENTITY(1,1) NOT NULL,
        InvoiceID            int           NOT NULL,
        CustomerID           int           NOT NULL,
        CityID               int           NULL,
        StockItemID          int           NULL,
        InvoiceDate          date          NOT NULL,
        Quantity             int           NOT NULL,
        UnitPrice            decimal(18,2) NOT NULL,
        LineTotal            decimal(18,2) NOT NULL,
        SalespersonPersonID  int           NULL,
        CONSTRAINT PK_Demo_LargeInvoiceFact PRIMARY KEY CLUSTERED (InvoiceFactID)
    );
    PRINT '[OK]  Created table Demo.LargeInvoiceFact.';
END
ELSE
    PRINT '[INFO] Table Demo.LargeInvoiceFact already exists.';
GO

/* 3) Workload log: one row per workload phase run. The Query Store report
      scripts join to this so they only show queries from the run you care about. */
IF OBJECT_ID(N'Demo.WorkloadLog', N'U') IS NULL
BEGIN
    CREATE TABLE Demo.WorkloadLog
    (
        WorkloadLogID  int           IDENTITY(1,1) NOT NULL,
        RunLabel       nvarchar(100) NOT NULL,   -- e.g. 'baseline', 'regressed', 'fixed'
        Phase          nvarchar(50)  NOT NULL,   -- free-form sub-phase / scenario name
        StartedAt      datetime2(3)  NOT NULL CONSTRAINT DF_Demo_WorkloadLog_StartedAt DEFAULT (SYSUTCDATETIME()),
        EndedAt        datetime2(3)  NULL,
        Iterations     int           NULL,
        Notes          nvarchar(400) NULL,
        CONSTRAINT PK_Demo_WorkloadLog PRIMARY KEY CLUSTERED (WorkloadLogID)
    );
    PRINT '[OK]  Created table Demo.WorkloadLog.';
END
ELSE
    PRINT '[INFO] Table Demo.WorkloadLog already exists.';
GO

PRINT 'Next: 02b-amplify-demo-data.sql to populate Demo.LargeInvoiceFact.';
GO
