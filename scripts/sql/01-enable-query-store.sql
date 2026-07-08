/* =============================================================================
   01-enable-query-store.sql

   Purpose : Turn on Query Store for WideWorldImporters and configure it for a
             live demo (fast aggregation, capture everything). Query Store is the
             "flight recorder" the demo uses as the source of truth for the
             regression investigation.
   Run as  : A login with ALTER on the database (db_owner is simplest for setup).
   Safe    : Changes database-scoped Query Store settings only. No data changes.

   NOTE on DEMO vs PRODUCTION settings (read before using elsewhere):
     - INTERVAL_LENGTH_MINUTES = 1 gives near-real-time aggregation so the demo
       shows regressions within a minute. In production 15 or 60 is typical to
       limit overhead and storage.
     - QUERY_CAPTURE_MODE = ALL captures every query, ideal for a controlled demo
       on a small database. In production prefer AUTO (skips trivial/infrequent
       queries) to reduce overhead.
     - MAX_STORAGE_SIZE_MB and the cleanup policy below are sized for a demo.
   ============================================================================= */
SET NOCOUNT ON;
USE WideWorldImporters;
GO

/* 1) Enable Query Store (no-op if already on). */
IF (SELECT actual_state FROM sys.database_query_store_options) = 0
BEGIN
    PRINT '[INFO] Enabling Query Store...';
    ALTER DATABASE WideWorldImporters SET QUERY_STORE = ON;
END
ELSE
    PRINT '[INFO] Query Store already enabled; (re)applying demo configuration...';
GO

/* 2) Configure for the demo. */
ALTER DATABASE WideWorldImporters SET QUERY_STORE
(
    OPERATION_MODE              = READ_WRITE,
    DATA_FLUSH_INTERVAL_SECONDS = 60,
    INTERVAL_LENGTH_MINUTES     = 1,            -- demo: fast buckets; prod: 15 or 60
    MAX_STORAGE_SIZE_MB         = 1024,
    QUERY_CAPTURE_MODE          = ALL,          -- demo: capture everything; prod: AUTO
    SIZE_BASED_CLEANUP_MODE     = AUTO,
    MAX_PLANS_PER_QUERY         = 200,
    WAIT_STATS_CAPTURE_MODE     = ON,
    CLEANUP_POLICY              = (STALE_QUERY_THRESHOLD_DAYS = 30)
);
GO

/* 3) OPTIONAL: start the demo from a clean slate by clearing prior history.
      Uncomment for a pristine before/after story. Destroys existing QS data only. */
-- ALTER DATABASE WideWorldImporters SET QUERY_STORE CLEAR ALL;
-- GO

/* 4) Verify configuration. */
PRINT '== Query Store configuration ==';
SELECT
    desired_state_desc,
    actual_state_desc,
    operation_mode_desc          = readonly_reason,   -- 0 when read-write
    query_capture_mode_desc,
    interval_length_minutes,
    max_storage_size_mb,
    current_storage_size_mb,
    flush_interval_seconds       = flush_interval_seconds,
    stale_query_threshold_days   = stale_query_threshold_days,
    wait_stats_capture_mode_desc
FROM sys.database_query_store_options;
GO

IF (SELECT actual_state FROM sys.database_query_store_options) = 2
    PRINT '[OK]  Query Store is ON and READ_WRITE. Ready to capture the demo workload.';
ELSE
    PRINT '[WARN] Query Store is not in READ_WRITE state. Check actual_state_desc above.';
GO
