/* =============================================================================
   09-query-store-regression-report.sql

  Purpose : Prove the regression with Query Store data. Shows the regressed run's
         numbers and compares each _Regressed procedure with its logical
         _Baseline procedure family. The variants have different query_id
         values because they are different stored procedures; both IDs are
         reported explicitly.
   Run as  : A login with VIEW DATABASE STATE.
   Safe    : Read-only. Uses temp tables.

   READING THE OUTPUT:
     - duration_x / cpu_x / reads_x are "regressed / baseline" ratios. A value of
       50 means the regressed run was ~50x slower / more expensive.
     - access_path_changed compares the captured plan shapes (seek/scan). It is
       not a same-query plan change because each procedure variant has its own
       query_id.
   ============================================================================= */
SET NOCOUNT ON;
USE WideWorldImporters;
GO

/* 1) Resolve the two run windows (latest completed or active run of each). */
DECLARE @bStart datetime2(3), @bEnd datetime2(3), @bId int;
SELECT TOP (1) @bId = WorkloadLogID, @bStart = StartedAt, @bEnd = ISNULL(EndedAt, SYSUTCDATETIME())
FROM Demo.WorkloadLog WHERE RunLabel = N'baseline' ORDER BY WorkloadLogID DESC;

DECLARE @rStart datetime2(3), @rEnd datetime2(3), @rId int;
SELECT TOP (1) @rId = WorkloadLogID, @rStart = StartedAt, @rEnd = ISNULL(EndedAt, SYSUTCDATETIME())
FROM Demo.WorkloadLog WHERE RunLabel = N'regressed' ORDER BY WorkloadLogID DESC;

IF @bId IS NULL OR @rId IS NULL
BEGIN
  PRINT 'Both baseline and regressed workload runs are required. Run 05, then 06 and 07.';
    RETURN;
END;

DECLARE @bStartOff datetimeoffset = TODATETIMEOFFSET(DATEADD(MINUTE, -1, @bStart), 0);
DECLARE @bEndOff   datetimeoffset = TODATETIMEOFFSET(DATEADD(MINUTE,  1, @bEnd),   0);
DECLARE @rStartOff datetimeoffset = TODATETIMEOFFSET(DATEADD(MINUTE, -1, @rStart), 0);
DECLARE @rEndOff   datetimeoffset = TODATETIMEOFFSET(DATEADD(MINUTE,  1, @rEnd),   0);

/* 2) Aggregate the principal fact-table statement for each procedure variant.
      Query Store identifies the variants separately, so query_family removes
      only the phase suffix for the side-by-side comparison. */
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

-- baseline window
INSERT #agg
SELECT 'baseline', LEFT(o.name, LEN(o.name) - 9), o.name, q.query_id,
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
  AND RIGHT(o.name, 9) = N'_Baseline'
  AND qt.query_sql_text LIKE N'%Demo.LargeInvoiceFact%'
  AND rsi.start_time < @bEndOff AND rsi.end_time > @bStartOff
GROUP BY o.name, q.query_id;

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

IF NOT EXISTS (SELECT 1 FROM #agg WHERE phase = 'baseline')
   OR NOT EXISTS (SELECT 1 FROM #agg WHERE phase = 'regressed')
BEGIN
    DROP TABLE #agg;
    THROW 51001, 'Query Store has not aggregated both phases yet. Wait for the capture interval, then rerun this report.', 1;
END;

/* 3) Regressed-run detail. */
PRINT CONCAT('== Regressed run detail (WorkloadLogID=', @rId, ') ==');
SELECT query_family, object_name, query_id, representative_plan_id, total_executions,
       avg_duration_ms, avg_cpu_ms, avg_logical_reads, distinct_plans, access_path
FROM #agg WHERE phase = 'regressed'
ORDER BY avg_duration_ms DESC;

/* 4) Logical family comparison (the punchline). */
PRINT '== Baseline vs Regressed variants (ratios = regressed / baseline) ==';
SELECT
    query_family          = COALESCE(b.query_family, r.query_family),
    baseline_object       = b.object_name,
    regressed_object      = r.object_name,
    baseline_query_id     = b.query_id,
    regressed_query_id    = r.query_id,
    baseline_plan_id      = b.representative_plan_id,
    regressed_plan_id     = r.representative_plan_id,
    baseline_executions   = b.total_executions,
    regressed_executions  = r.total_executions,
    base_avg_ms           = b.avg_duration_ms,
    reg_avg_ms            = r.avg_duration_ms,
    duration_x            = CONVERT(decimal(18,1), r.avg_duration_ms / NULLIF(b.avg_duration_ms, 0)),
    base_cpu_ms           = b.avg_cpu_ms,
    reg_cpu_ms            = r.avg_cpu_ms,
    cpu_x                 = CONVERT(decimal(18,1), r.avg_cpu_ms / NULLIF(b.avg_cpu_ms, 0)),
    base_reads            = b.avg_logical_reads,
    reg_reads             = r.avg_logical_reads,
    reads_x               = CONVERT(decimal(18,1), 1.0 * r.avg_logical_reads / NULLIF(b.avg_logical_reads, 0)),
    baseline_access_path  = b.access_path,
    regressed_access_path = r.access_path,
    access_path_changed   = CASE WHEN b.access_path <> r.access_path THEN 1 ELSE 0 END,
    baseline_plan_count   = b.distinct_plans,
    regressed_plan_count  = r.distinct_plans
FROM (SELECT * FROM #agg WHERE phase = 'baseline')  AS b
FULL JOIN (SELECT * FROM #agg WHERE phase = 'regressed') AS r
       ON r.query_family = b.query_family
ORDER BY duration_x DESC;

DROP TABLE #agg;
GO
