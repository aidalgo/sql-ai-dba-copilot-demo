/* =============================================================================
   12-query-store-after-fix-report.sql

  Purpose : Prove the fix worked. Compares each _Regressed procedure with its
         logical _Fixed procedure family. The variants have different
         query_id values because they are different stored procedures; both
         IDs are reported explicitly.
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

IF @rId IS NULL OR @fId IS NULL
BEGIN
  PRINT 'Both regressed and fixed workload runs are required. Run 07, then apply 10 and run 11.';
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
    query_family      sysname,
    object_name       sysname,
    query_id          bigint,
    representative_plan_id bigint,
    total_executions  bigint,
    avg_duration_ms   decimal(18, 2),
    avg_cpu_ms        decimal(18, 2),
    avg_logical_reads bigint,
    distinct_plans    int,
    access_path       varchar(20)
);

-- regressed window
INSERT #agg
SELECT 'regressed', LEFT(o.name, LEN(o.name) - 10), o.name, q.query_id,
       MIN(p.plan_id),
       SUM(rs.count_executions),
       CONVERT(decimal(18,2), SUM(rs.avg_duration * rs.count_executions) / NULLIF(SUM(rs.count_executions),0) / 1000.0),
       CONVERT(decimal(18,2), SUM(rs.avg_cpu_time  * rs.count_executions) / NULLIF(SUM(rs.count_executions),0) / 1000.0),
       CONVERT(bigint,        SUM(rs.avg_logical_io_reads * rs.count_executions) / NULLIF(SUM(rs.count_executions),0)),
       COUNT(DISTINCT p.plan_id),
       CASE
           WHEN MAX(CASE WHEN p.query_plan LIKE N'%PhysicalOp="Index Seek"%'
                               OR p.query_plan LIKE N'%PhysicalOp="Clustered Index Seek"%' THEN 1 ELSE 0 END) = 1
            AND MAX(CASE WHEN p.query_plan LIKE N'%PhysicalOp="Index Scan"%'
                               OR p.query_plan LIKE N'%PhysicalOp="Clustered Index Scan"%'
                               OR p.query_plan LIKE N'%PhysicalOp="Table Scan"%' THEN 1 ELSE 0 END) = 0 THEN 'seek'
           WHEN MAX(CASE WHEN p.query_plan LIKE N'%PhysicalOp="Index Scan"%'
                               OR p.query_plan LIKE N'%PhysicalOp="Clustered Index Scan"%'
                               OR p.query_plan LIKE N'%PhysicalOp="Table Scan"%' THEN 1 ELSE 0 END) = 1
            AND MAX(CASE WHEN p.query_plan LIKE N'%PhysicalOp="Index Seek"%'
                               OR p.query_plan LIKE N'%PhysicalOp="Clustered Index Seek"%' THEN 1 ELSE 0 END) = 0 THEN 'scan'
           WHEN MAX(CASE WHEN p.query_plan LIKE N'%PhysicalOp="Index Seek"%'
                               OR p.query_plan LIKE N'%PhysicalOp="Clustered Index Seek"%'
                               OR p.query_plan LIKE N'%PhysicalOp="Index Scan"%'
                               OR p.query_plan LIKE N'%PhysicalOp="Clustered Index Scan"%'
                               OR p.query_plan LIKE N'%PhysicalOp="Table Scan"%' THEN 1 ELSE 0 END) = 1 THEN 'mixed'
           ELSE 'other'
       END
FROM sys.query_store_query                  AS q
JOIN sys.query_store_query_text             AS qt  ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_plan                   AS p   ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats          AS rs  ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval AS rsi ON rsi.runtime_stats_interval_id = rs.runtime_stats_interval_id
JOIN sys.objects                            AS o   ON o.object_id = q.object_id
WHERE o.schema_id = SCHEMA_ID(N'Demo')
  AND o.type = N'P'
  AND RIGHT(o.name, 10) = N'_Regressed'
  AND qt.query_sql_text LIKE N'%Demo.LargeInvoiceFact%'
  AND rsi.start_time < @rEndOff AND rsi.end_time > @rStartOff
GROUP BY o.name, q.query_id;

-- fixed window
INSERT #agg
SELECT 'fixed', LEFT(o.name, LEN(o.name) - 6), o.name, q.query_id,
       MIN(p.plan_id),
       SUM(rs.count_executions),
       CONVERT(decimal(18,2), SUM(rs.avg_duration * rs.count_executions) / NULLIF(SUM(rs.count_executions),0) / 1000.0),
       CONVERT(decimal(18,2), SUM(rs.avg_cpu_time  * rs.count_executions) / NULLIF(SUM(rs.count_executions),0) / 1000.0),
       CONVERT(bigint,        SUM(rs.avg_logical_io_reads * rs.count_executions) / NULLIF(SUM(rs.count_executions),0)),
       COUNT(DISTINCT p.plan_id),
       CASE
           WHEN MAX(CASE WHEN p.query_plan LIKE N'%PhysicalOp="Index Seek"%'
                               OR p.query_plan LIKE N'%PhysicalOp="Clustered Index Seek"%' THEN 1 ELSE 0 END) = 1
            AND MAX(CASE WHEN p.query_plan LIKE N'%PhysicalOp="Index Scan"%'
                               OR p.query_plan LIKE N'%PhysicalOp="Clustered Index Scan"%'
                               OR p.query_plan LIKE N'%PhysicalOp="Table Scan"%' THEN 1 ELSE 0 END) = 0 THEN 'seek'
           WHEN MAX(CASE WHEN p.query_plan LIKE N'%PhysicalOp="Index Scan"%'
                               OR p.query_plan LIKE N'%PhysicalOp="Clustered Index Scan"%'
                               OR p.query_plan LIKE N'%PhysicalOp="Table Scan"%' THEN 1 ELSE 0 END) = 1
            AND MAX(CASE WHEN p.query_plan LIKE N'%PhysicalOp="Index Seek"%'
                               OR p.query_plan LIKE N'%PhysicalOp="Clustered Index Seek"%' THEN 1 ELSE 0 END) = 0 THEN 'scan'
           WHEN MAX(CASE WHEN p.query_plan LIKE N'%PhysicalOp="Index Seek"%'
                               OR p.query_plan LIKE N'%PhysicalOp="Clustered Index Seek"%'
                               OR p.query_plan LIKE N'%PhysicalOp="Index Scan"%'
                               OR p.query_plan LIKE N'%PhysicalOp="Clustered Index Scan"%'
                               OR p.query_plan LIKE N'%PhysicalOp="Table Scan"%' THEN 1 ELSE 0 END) = 1 THEN 'mixed'
           ELSE 'other'
       END
FROM sys.query_store_query                  AS q
JOIN sys.query_store_query_text             AS qt  ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_plan                   AS p   ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats          AS rs  ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval AS rsi ON rsi.runtime_stats_interval_id = rs.runtime_stats_interval_id
JOIN sys.objects                            AS o   ON o.object_id = q.object_id
WHERE o.schema_id = SCHEMA_ID(N'Demo')
  AND o.type = N'P'
  AND RIGHT(o.name, 6) = N'_Fixed'
  AND qt.query_sql_text LIKE N'%Demo.LargeInvoiceFact%'
  AND rsi.start_time < @fEndOff AND rsi.end_time > @fStartOff
GROUP BY o.name, q.query_id;

IF NOT EXISTS (SELECT 1 FROM #agg WHERE phase = 'regressed')
   OR NOT EXISTS (SELECT 1 FROM #agg WHERE phase = 'fixed')
BEGIN
    DROP TABLE #agg;
    THROW 51002, 'Query Store has not aggregated both phases yet. Wait for the capture interval, then rerun this report.', 1;
END;

/* Fixed-run detail. */
PRINT CONCAT('== Fixed run detail (WorkloadLogID=', @fId, ') ==');
SELECT query_family, object_name, query_id, representative_plan_id, total_executions,
       avg_duration_ms, avg_cpu_ms, avg_logical_reads, distinct_plans, access_path
FROM #agg WHERE phase = 'fixed'
ORDER BY avg_duration_ms DESC;

/* Regressed vs fixed comparison (the proof). */
PRINT '== Regressed vs Fixed variants (speedup_x = regressed / fixed) ==';
SELECT
    query_family         = COALESCE(r.query_family, f.query_family),
    regressed_object     = r.object_name,
    fixed_object         = f.object_name,
    regressed_query_id   = r.query_id,
    fixed_query_id       = f.query_id,
    regressed_plan_id    = r.representative_plan_id,
    fixed_plan_id        = f.representative_plan_id,
    regressed_executions = r.total_executions,
    fixed_executions     = f.total_executions,
    reg_avg_ms           = r.avg_duration_ms,
    fix_avg_ms           = f.avg_duration_ms,
    speedup_x            = CONVERT(decimal(18,1), r.avg_duration_ms / NULLIF(f.avg_duration_ms, 0)),
    reg_cpu_ms           = r.avg_cpu_ms,
    fix_cpu_ms           = f.avg_cpu_ms,
    cpu_speedup          = CONVERT(decimal(18,1), r.avg_cpu_ms / NULLIF(f.avg_cpu_ms, 0)),
    reg_reads            = r.avg_logical_reads,
    fix_reads            = f.avg_logical_reads,
    reads_drop           = CONVERT(decimal(18,1), 1.0 * r.avg_logical_reads / NULLIF(f.avg_logical_reads, 0)),
    regressed_access_path = r.access_path,
    fixed_access_path     = f.access_path,
    access_path_changed   = CASE WHEN r.access_path <> f.access_path THEN 1 ELSE 0 END,
    regressed_plan_count  = r.distinct_plans,
    fixed_plan_count      = f.distinct_plans
FROM (SELECT * FROM #agg WHERE phase = 'regressed') AS r
FULL JOIN (SELECT * FROM #agg WHERE phase = 'fixed') AS f
       ON f.query_family = r.query_family
ORDER BY speedup_x DESC;

DROP TABLE #agg;
GO
