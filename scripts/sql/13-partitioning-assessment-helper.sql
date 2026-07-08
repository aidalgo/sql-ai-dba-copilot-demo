/* =============================================================================
   13-partitioning-assessment-helper.sql

   Purpose : Provide the facts you need to decide WHETHER table partitioning is
             worth considering for Demo.LargeInvoiceFact -- and to push back when
             it is suggested as a reflex.

   *** IMPORTANT CAVEAT -- READ THIS FIRST ***
     Partitioning is NOT a generic query-tuning fix. It is primarily a
     data-management feature (fast switch-in/switch-out, piecemeal maintenance,
     aligned index maintenance on very large tables). It does NOT make a
     non-sargable predicate sargable, and on its own it rarely beats a good
     index for selective queries. In THIS demo the real fix is (1) restoring the
     sargable date predicate and (2) recreating the supporting index -- NOT
     partitioning. Use this script to demonstrate that reasoning, not to justify
     partitioning by default. Only consider partitioning when you have a genuine
     large-table data-lifecycle or maintenance-window problem.

   Run as  : A login with VIEW DATABASE STATE / VIEW DEFINITION.
   Safe    : Read-only.
   ============================================================================= */
SET NOCOUNT ON;
USE WideWorldImporters;
GO

DECLARE @object_id int = OBJECT_ID(N'Demo.LargeInvoiceFact');
IF @object_id IS NULL
BEGIN
    PRINT 'Demo.LargeInvoiceFact does not exist. Run 02-create-demo-schema.sql and 02b-amplify-demo-data.sql first.';
    RETURN;
END;

/* 1) Overall size: rows and space. */
PRINT '== Table size ==';
SELECT
    [table]        = N'Demo.LargeInvoiceFact',
    total_rows     = SUM(CASE WHEN ps.index_id IN (0,1) THEN ps.row_count ELSE 0 END),
    reserved_MB    = CONVERT(decimal(18,2), SUM(ps.reserved_page_count) * 8.0 / 1024),
    used_MB        = CONVERT(decimal(18,2), SUM(ps.used_page_count)     * 8.0 / 1024),
    partition_count= COUNT(DISTINCT ps.partition_number)
FROM sys.dm_db_partition_stats AS ps
WHERE ps.object_id = @object_id;

/* 2) Is it already partitioned, and on what scheme? */
PRINT '== Partitioning status ==';
SELECT
    index_name      = i.name,
    i.type_desc,
    data_space      = ds.name,
    data_space_type = ds.type_desc,          -- ROWS = heap/B-tree on a filegroup; PS = partition scheme
    partition_count = (SELECT COUNT(*) FROM sys.partitions p WHERE p.object_id = i.object_id AND p.index_id = i.index_id)
FROM sys.indexes i
JOIN sys.data_spaces ds ON ds.data_space_id = i.data_space_id
WHERE i.object_id = @object_id
ORDER BY i.index_id;

/* 3) Row distribution by YEAR -- does the data align with a range strategy? */
PRINT '== Row distribution by year ==';
SELECT
    [year]   = YEAR(InvoiceDate),
    [rows]   = COUNT_BIG(*),
    pct_of_total = CONVERT(decimal(5,2), 100.0 * COUNT_BIG(*) / SUM(COUNT_BIG(*)) OVER ())
FROM Demo.LargeInvoiceFact
GROUP BY YEAR(InvoiceDate)
ORDER BY [year];

/* 4) Row distribution by year-month (skew check for the most recent years). */
PRINT '== Row distribution by year-month (top 24 buckets) ==';
SELECT TOP (24)
    yyyymm = CONVERT(char(7), DATEFROMPARTS(YEAR(InvoiceDate), MONTH(InvoiceDate), 1), 126),
    [rows] = COUNT_BIG(*)
FROM Demo.LargeInvoiceFact
GROUP BY YEAR(InvoiceDate), MONTH(InvoiceDate)
ORDER BY yyyymm DESC;

/* 5) Existing indexes and their key/included columns. */
PRINT '== Existing indexes on Demo.LargeInvoiceFact ==';
SELECT
    index_name = i.name,
    i.type_desc,
    is_unique  = i.is_unique,
    key_columns = STUFF((
        SELECT ', ' + c.name + CASE WHEN ic.is_descending_key = 1 THEN ' DESC' ELSE '' END
        FROM sys.index_columns ic
        JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0
        ORDER BY ic.key_ordinal
        FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, ''),
    included_columns = STUFF((
        SELECT ', ' + c.name
        FROM sys.index_columns ic
        JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 1
        ORDER BY ic.index_column_id
        FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, '')
FROM sys.indexes i
WHERE i.object_id = @object_id AND i.type > 0   -- skip the heap row
ORDER BY i.index_id;
GO

/* =============================================================================
   DECISION CHECKLIST (answer these before proposing partitioning)
   -----------------------------------------------------------------------------
   [ ] Is the query slow because of a NON-SARGABLE predicate or a MISSING index?
         -> If yes (as in this demo), fix THAT first. Partitioning will not help
            and may even hurt (partition management overhead).
   [ ] Do you have a data-lifecycle need: archive/purge old data, or load/switch
         large batches with minimal blocking? -> Partitioning shines here.
   [ ] Is the table truly large (commonly hundreds of millions+ rows) AND causing
         maintenance-window pain (index rebuilds, stats, backups)?
   [ ] Will queries actually benefit from partition elimination, i.e. do they
         filter on the partitioning key with sargable predicates?
   [ ] Have you accounted for: aligned vs non-aligned indexes, partition function
         maintenance, and the SARG requirement on the partition key?
   If most boxes are unchecked, DO NOT partition -- tune the query and indexes.
   ============================================================================= */
