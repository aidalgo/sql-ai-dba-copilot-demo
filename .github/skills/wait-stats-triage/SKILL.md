---
name: wait-stats-triage
description: Summarize SQL Server wait statistics and point to next steps. Use when asked what the instance is waiting on, the top waits, or where time is being spent.
---

# Wait-stats triage

**Read-only.**

## Steps

1. Query `sys.dm_os_wait_stats`.
2. Exclude benign/background waits (e.g. `SLEEP_*`, `*_QUEUE`, `XE_TIMER`,
   `BROKER_*`, `LAZYWRITER_SLEEP`, `DIRTY_PAGE_POLL`, `SQLTRACE_*`, `WAIT_XTP_*`,
   `HADR_FILESTREAM_IOMGR_IOCOMPLETION`).
3. Rank the rest by `wait_time_ms`; compute each as a % of the total.
4. Return the top 10 with: `wait_type`, wait time (s), % of total, average wait
   (ms), and a one-line "what this usually means / what to check next".

## Reading the results

- These are **cumulative** since the last restart (or last
  `DBCC SQLPERF('sys.dm_os_wait_stats', CLEAR)`). Say so.
- Common mappings:
  - `PAGEIOLATCH_*` → storage / read latency (or missing indexes causing scans).
  - `LCK_M_*` → blocking (pair with `blocking-chain-triage`).
  - `CXPACKET` / `CXCONSUMER` → parallelism (check MAXDOP / cost threshold).
  - `SOS_SCHEDULER_YIELD` → CPU pressure.
  - `RESOURCE_SEMAPHORE` → memory-grant pressure.
  - `WRITELOG` → transaction-log latency.

## Recommend, don't act

Point to the next diagnostic; do not change server settings. If a DMV is blocked
by permissions, note that `VIEW SERVER STATE` is required.
