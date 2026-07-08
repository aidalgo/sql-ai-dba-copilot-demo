/* =============================================================================
   08-query-store-baseline-report.sql

   Purpose : Show the "healthy" baseline numbers Query Store captured for the demo
             procedures during the most recent baseline workload. Use this to
             establish the before picture (fast seeks, low CPU/reads).
   Run as  : A login with VIEW DATABASE STATE (to read the sys.query_store_* DMVs).
   Safe    : Read-only.

   HOW IT SCOPES THE RUN: it finds the latest Demo.WorkloadLog row with
   RunLabel = 'baseline' and reports only Query Store intervals overlapping that
   run's UTC time window, restricted to queries inside the Demo procedures.
   ============================================================================= */
SET NOCOUNT ON;
USE WideWorldImporters;
GO

DECLARE @label nvarchar(100) = N'baseline';

DECLARE @logId int, @start datetime2(3), @end datetime2(3);
SELECT TOP (1)
    @logId = WorkloadLogID,
    @start = StartedAt,
    @end   = ISNULL(EndedAt, SYSUTCDATETIME())
FROM Demo.WorkloadLog
WHERE RunLabel = @label
ORDER BY WorkloadLogID DESC;

IF @logId IS NULL
BEGIN
    PRINT 'No "baseline" workload run found. Run 05-run-baseline-workload.sql first.';
    RETURN;
END;

-- Convert the window to datetimeoffset (Query Store stores UTC) with a 1-minute grace.
DECLARE @startOff datetimeoffset = TODATETIMEOFFSET(DATEADD(MINUTE, -1, @start), 0);
DECLARE @endOff   datetimeoffset = TODATETIMEOFFSET(DATEADD(MINUTE,  1, @end),   0);

PRINT CONCAT('== Baseline report for WorkloadLogID=', @logId,
             '  Window(UTC) ', CONVERT(varchar(30), @start, 126), ' .. ', CONVERT(varchar(30), @end, 126), ' ==');

SELECT
    object_name       = OBJECT_NAME(q.object_id),
    q.query_id,
    p.plan_id,
    p.is_forced_plan,
    total_executions  = SUM(rs.count_executions),
    avg_duration_ms   = CONVERT(decimal(18, 2), SUM(rs.avg_duration   * rs.count_executions) / NULLIF(SUM(rs.count_executions), 0) / 1000.0),
    avg_cpu_ms        = CONVERT(decimal(18, 2), SUM(rs.avg_cpu_time    * rs.count_executions) / NULLIF(SUM(rs.count_executions), 0) / 1000.0),
    avg_logical_reads = CONVERT(bigint,         SUM(rs.avg_logical_io_reads * rs.count_executions) / NULLIF(SUM(rs.count_executions), 0)),
    max_duration_ms   = CONVERT(decimal(18, 2), MAX(rs.max_duration) / 1000.0),
    query_sql_text    = MIN(qt.query_sql_text)
FROM sys.query_store_query                AS q
JOIN sys.query_store_query_text           AS qt  ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_plan                 AS p   ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats        AS rs  ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval AS rsi ON rsi.runtime_stats_interval_id = rs.runtime_stats_interval_id
WHERE q.object_id IN (SELECT object_id FROM sys.objects WHERE schema_id = SCHEMA_ID('Demo') AND type = 'P')
  AND rsi.start_time < @endOff
  AND rsi.end_time   > @startOff
GROUP BY q.object_id, q.query_id, p.plan_id, p.is_forced_plan
ORDER BY avg_duration_ms DESC;
GO
