/* =============================================================================
   14-show-query-store-plan-details.sql

   Purpose : Drill into a single query_id: show its text, every plan Query Store
             has for it (with the showplan XML you can click in SSMS), whether any
             plan is forced, and per-plan runtime stats. Use this after a report
             (08/09/12) hands you an interesting query_id.
   Run as  : A login with VIEW DATABASE STATE.
   Safe    : Read-only.

   USAGE: set @query_id below to the value from a report, then run.
   ============================================================================= */
SET NOCOUNT ON;
USE WideWorldImporters;
GO

DECLARE @query_id bigint = 0;   -- <-- set to the query_id you want to inspect

IF NOT EXISTS (SELECT 1 FROM sys.query_store_query WHERE query_id = @query_id)
BEGIN
    PRINT CONCAT('query_id ', @query_id, ' not found in Query Store. Set @query_id to a value from a report (08/09/12).');
    RETURN;
END;

/* 1) Query text + owning object. */
PRINT '== Query text ==';
SELECT
    q.query_id,
    object_name = OBJECT_NAME(q.object_id),
    qt.query_sql_text
FROM sys.query_store_query      AS q
JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
WHERE q.query_id = @query_id;

/* 2) All plans for this query, with the clickable showplan XML. */
PRINT '== Plans (click query_plan to open the graphical plan in SSMS) ==';
SELECT
    p.plan_id,
    p.is_forced_plan,
    p.last_force_failure_reason_desc,
    p.initial_compile_start_time,
    p.last_compile_start_time,
    p.count_compiles,
    query_plan = TRY_CONVERT(xml, p.query_plan)
FROM sys.query_store_plan AS p
WHERE p.query_id = @query_id
ORDER BY p.plan_id;

/* 3) Per-plan runtime stats (all captured history for this query). */
PRINT '== Per-plan runtime stats ==';
SELECT
    p.plan_id,
    p.is_forced_plan,
    total_executions  = SUM(rs.count_executions),
    avg_duration_ms   = CONVERT(decimal(18,2), SUM(rs.avg_duration * rs.count_executions) / NULLIF(SUM(rs.count_executions),0) / 1000.0),
    avg_cpu_ms        = CONVERT(decimal(18,2), SUM(rs.avg_cpu_time  * rs.count_executions) / NULLIF(SUM(rs.count_executions),0) / 1000.0),
    avg_logical_reads = CONVERT(bigint,        SUM(rs.avg_logical_io_reads * rs.count_executions) / NULLIF(SUM(rs.count_executions),0)),
    max_duration_ms   = CONVERT(decimal(18,2), MAX(rs.max_duration) / 1000.0),
    first_execution   = MIN(rs.first_execution_time),
    last_execution    = MAX(rs.last_execution_time)
FROM sys.query_store_plan          AS p
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
WHERE p.query_id = @query_id
GROUP BY p.plan_id, p.is_forced_plan
ORDER BY avg_duration_ms DESC;
GO
