/* =============================================================================
   09-query-store-regression-report.sql

   Purpose : Prove the regression with Query Store data. Shows the regressed run's
             numbers AND a side-by-side comparison against the baseline run for the
             same queries, so you can quantify exactly how much slower things got
             and whether the plan changed (seek -> scan).
   Run as  : A login with VIEW DATABASE STATE.
   Safe    : Read-only. Uses temp tables.

   READING THE OUTPUT:
     - duration_x / cpu_x / reads_x are "regressed / baseline" ratios. A value of
       50 means the regressed run was ~50x slower / more expensive.
     - base_plans vs reg_plans > 1, or different plan_ids, indicates a plan change.
   ============================================================================= */
SET NOCOUNT ON;
USE WideWorldImporters;
GO

/* 1) Resolve the two run windows (latest of each). */
DECLARE @bStart datetime2(3), @bEnd datetime2(3), @bId int;
SELECT TOP (1) @bId = WorkloadLogID, @bStart = StartedAt, @bEnd = ISNULL(EndedAt, SYSUTCDATETIME())
FROM Demo.WorkloadLog WHERE RunLabel = N'baseline' ORDER BY WorkloadLogID DESC;

DECLARE @rStart datetime2(3), @rEnd datetime2(3), @rId int;
SELECT TOP (1) @rId = WorkloadLogID, @rStart = StartedAt, @rEnd = ISNULL(EndedAt, SYSUTCDATETIME())
FROM Demo.WorkloadLog WHERE RunLabel = N'regressed' ORDER BY WorkloadLogID DESC;

IF @rId IS NULL
BEGIN
    PRINT 'No "regressed" workload run found. Run 06-introduce-performance-issue.sql then 07-run-regressed-workload.sql.';
    RETURN;
END;

DECLARE @bStartOff datetimeoffset = TODATETIMEOFFSET(DATEADD(MINUTE, -1, @bStart), 0);
DECLARE @bEndOff   datetimeoffset = TODATETIMEOFFSET(DATEADD(MINUTE,  1, @bEnd),   0);
DECLARE @rStartOff datetimeoffset = TODATETIMEOFFSET(DATEADD(MINUTE, -1, @rStart), 0);
DECLARE @rEndOff   datetimeoffset = TODATETIMEOFFSET(DATEADD(MINUTE,  1, @rEnd),   0);

/* 2) Aggregate per query for each window into a temp table. */
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

-- baseline window
IF @bId IS NOT NULL
INSERT #agg
SELECT 'baseline', OBJECT_NAME(q.object_id), q.query_id,
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
  AND rsi.start_time < @bEndOff AND rsi.end_time > @bStartOff
GROUP BY q.object_id, q.query_id;

-- regressed window
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

/* 3) Regressed-run detail. */
PRINT CONCAT('== Regressed run detail (WorkloadLogID=', @rId, ') ==');
SELECT object_name, query_id, total_executions, avg_duration_ms, avg_cpu_ms, avg_logical_reads, distinct_plans
FROM #agg WHERE phase = 'regressed'
ORDER BY avg_duration_ms DESC;

/* 4) Baseline vs regressed comparison (the punchline). */
PRINT '== Baseline vs Regressed (ratios = regressed / baseline) ==';
SELECT
    object_name = COALESCE(b.object_name, r.object_name),
    query_id    = COALESCE(b.query_id, r.query_id),
    base_avg_ms = b.avg_duration_ms,
    reg_avg_ms  = r.avg_duration_ms,
    duration_x  = CONVERT(decimal(18,1), r.avg_duration_ms   / NULLIF(b.avg_duration_ms, 0)),
    base_cpu_ms = b.avg_cpu_ms,
    reg_cpu_ms  = r.avg_cpu_ms,
    cpu_x       = CONVERT(decimal(18,1), r.avg_cpu_ms        / NULLIF(b.avg_cpu_ms, 0)),
    base_reads  = b.avg_logical_reads,
    reg_reads   = r.avg_logical_reads,
    reads_x     = CONVERT(decimal(18,1), 1.0 * r.avg_logical_reads / NULLIF(b.avg_logical_reads, 0)),
    base_plans  = b.distinct_plans,
    reg_plans   = r.distinct_plans
FROM (SELECT * FROM #agg WHERE phase = 'baseline')  AS b
FULL JOIN (SELECT * FROM #agg WHERE phase = 'regressed') AS r
       ON r.query_id = b.query_id
ORDER BY duration_x DESC;

/* 5) Queries that ran under more than one plan during the regressed window. */
PRINT '== Queries with multiple plans in the regressed window (possible plan change) ==';
SELECT q.query_id, object_name = OBJECT_NAME(q.object_id), plan_count = COUNT(DISTINCT p.plan_id)
FROM sys.query_store_query                  AS q
JOIN sys.query_store_plan                   AS p   ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats          AS rs  ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval AS rsi ON rsi.runtime_stats_interval_id = rs.runtime_stats_interval_id
WHERE q.object_id IN (SELECT object_id FROM sys.objects WHERE schema_id = SCHEMA_ID('Demo') AND type = 'P')
  AND rsi.start_time < @rEndOff AND rsi.end_time > @rStartOff
GROUP BY q.query_id, q.object_id
HAVING COUNT(DISTINCT p.plan_id) > 1
ORDER BY plan_count DESC;

DROP TABLE #agg;
GO
