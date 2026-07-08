/* =============================================================================
   12-query-store-after-fix-report.sql

   Purpose : Prove the fix worked. Compares the regressed run against the fixed run
             for the same queries, so you can show the speed-up (e.g. "back to
             baseline" or "Nx faster than the regression").
   Run as  : A login with VIEW DATABASE STATE.
   Safe    : Read-only. Uses temp tables.

   READING THE OUTPUT:
     - speedup_x = regressed_avg_ms / fixed_avg_ms. A value of 50 means the fix
       made the query ~50x faster than the regression.
     - Compare fixed numbers back to 08-query-store-baseline-report.sql to confirm
       you returned to (or beat) the original healthy baseline.
   ============================================================================= */
SET NOCOUNT ON;
USE WideWorldImporters;
GO

DECLARE @rStart datetime2(3), @rEnd datetime2(3), @rId int;
SELECT TOP (1) @rId = WorkloadLogID, @rStart = StartedAt, @rEnd = ISNULL(EndedAt, SYSUTCDATETIME())
FROM Demo.WorkloadLog WHERE RunLabel = N'regressed' ORDER BY WorkloadLogID DESC;

DECLARE @fStart datetime2(3), @fEnd datetime2(3), @fId int;
SELECT TOP (1) @fId = WorkloadLogID, @fStart = StartedAt, @fEnd = ISNULL(EndedAt, SYSUTCDATETIME())
FROM Demo.WorkloadLog WHERE RunLabel = N'fixed' ORDER BY WorkloadLogID DESC;

IF @fId IS NULL
BEGIN
    PRINT 'No "fixed" workload run found. Apply 10-apply-fix-options.sql then run 11-run-fixed-workload.sql.';
    RETURN;
END;

DECLARE @rStartOff datetimeoffset = TODATETIMEOFFSET(DATEADD(MINUTE, -1, @rStart), 0);
DECLARE @rEndOff   datetimeoffset = TODATETIMEOFFSET(DATEADD(MINUTE,  1, @rEnd),   0);
DECLARE @fStartOff datetimeoffset = TODATETIMEOFFSET(DATEADD(MINUTE, -1, @fStart), 0);
DECLARE @fEndOff   datetimeoffset = TODATETIMEOFFSET(DATEADD(MINUTE,  1, @fEnd),   0);

IF OBJECT_ID('tempdb..#agg') IS NOT NULL DROP TABLE #agg;
CREATE TABLE #agg
(
    phase             varchar(20),
    object_name       sysname,
    query_id          bigint,
    total_executions  bigint,
    avg_duration_ms   decimal(18, 2),
    avg_cpu_ms        decimal(18, 2),
    avg_logical_reads bigint,
    distinct_plans    int
);

-- regressed window
IF @rId IS NOT NULL
INSERT #agg
SELECT 'regressed', OBJECT_NAME(q.object_id), q.query_id,
       SUM(rs.count_executions),
       CONVERT(decimal(18,2), SUM(rs.avg_duration * rs.count_executions) / NULLIF(SUM(rs.count_executions),0) / 1000.0),
       CONVERT(decimal(18,2), SUM(rs.avg_cpu_time  * rs.count_executions) / NULLIF(SUM(rs.count_executions),0) / 1000.0),
       CONVERT(bigint,        SUM(rs.avg_logical_io_reads * rs.count_executions) / NULLIF(SUM(rs.count_executions),0)),
       COUNT(DISTINCT p.plan_id)
FROM sys.query_store_query                  AS q
JOIN sys.query_store_plan                   AS p   ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats          AS rs  ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval AS rsi ON rsi.runtime_stats_interval_id = rs.runtime_stats_interval_id
WHERE q.object_id IN (SELECT object_id FROM sys.objects WHERE schema_id = SCHEMA_ID('Demo') AND type = 'P')
  AND rsi.start_time < @rEndOff AND rsi.end_time > @rStartOff
GROUP BY q.object_id, q.query_id;

-- fixed window
INSERT #agg
SELECT 'fixed', OBJECT_NAME(q.object_id), q.query_id,
       SUM(rs.count_executions),
       CONVERT(decimal(18,2), SUM(rs.avg_duration * rs.count_executions) / NULLIF(SUM(rs.count_executions),0) / 1000.0),
       CONVERT(decimal(18,2), SUM(rs.avg_cpu_time  * rs.count_executions) / NULLIF(SUM(rs.count_executions),0) / 1000.0),
       CONVERT(bigint,        SUM(rs.avg_logical_io_reads * rs.count_executions) / NULLIF(SUM(rs.count_executions),0)),
       COUNT(DISTINCT p.plan_id)
FROM sys.query_store_query                  AS q
JOIN sys.query_store_plan                   AS p   ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats          AS rs  ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval AS rsi ON rsi.runtime_stats_interval_id = rs.runtime_stats_interval_id
WHERE q.object_id IN (SELECT object_id FROM sys.objects WHERE schema_id = SCHEMA_ID('Demo') AND type = 'P')
  AND rsi.start_time < @fEndOff AND rsi.end_time > @fStartOff
GROUP BY q.object_id, q.query_id;

/* Fixed-run detail. */
PRINT CONCAT('== Fixed run detail (WorkloadLogID=', @fId, ') ==');
SELECT object_name, query_id, total_executions, avg_duration_ms, avg_cpu_ms, avg_logical_reads, distinct_plans
FROM #agg WHERE phase = 'fixed'
ORDER BY avg_duration_ms DESC;

/* Regressed vs fixed comparison (the proof). */
PRINT '== Regressed vs Fixed (speedup_x = regressed / fixed) ==';
SELECT
    object_name = COALESCE(r.object_name, f.object_name),
    query_id    = COALESCE(r.query_id, f.query_id),
    reg_avg_ms  = r.avg_duration_ms,
    fix_avg_ms  = f.avg_duration_ms,
    speedup_x   = CONVERT(decimal(18,1), r.avg_duration_ms   / NULLIF(f.avg_duration_ms, 0)),
    reg_cpu_ms  = r.avg_cpu_ms,
    fix_cpu_ms  = f.avg_cpu_ms,
    cpu_speedup = CONVERT(decimal(18,1), r.avg_cpu_ms        / NULLIF(f.avg_cpu_ms, 0)),
    reg_reads   = r.avg_logical_reads,
    fix_reads   = f.avg_logical_reads,
    reads_drop  = CONVERT(decimal(18,1), 1.0 * r.avg_logical_reads / NULLIF(f.avg_logical_reads, 0))
FROM (SELECT * FROM #agg WHERE phase = 'regressed') AS r
FULL JOIN (SELECT * FROM #agg WHERE phase = 'fixed') AS f
       ON f.query_id = r.query_id
ORDER BY speedup_x DESC;

DROP TABLE #agg;
GO
