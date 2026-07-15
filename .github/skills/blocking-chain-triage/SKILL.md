---
name: blocking-chain-triage
description: Triage live blocking in SQL Server — identify the head blocker, the blocked sessions, the blocked statements, and the lock resource. Use when queries are stuck, sessions are waiting on locks, or someone asks "who is blocking whom".
---

# Blocking chain triage

**Read-only.** Report and recommend. Do **not** `KILL` sessions or change anything.

## Steps

1. Snapshot current activity: join `sys.dm_exec_requests` (r) to
   `sys.dm_exec_sessions` (s) and `sys.dm_os_waiting_tasks` (w). Resolve the SQL
   text with `sys.dm_exec_sql_text(r.sql_handle)`.
2. Find the **head blocker**: the session that blocks others but is not itself
   blocked (its `blocking_session_id` is 0 while other sessions point to it).
3. For each blocked session, capture: `session_id`, blocked-by, `wait_type`,
   wait time (s), the lock resource (from `sys.dm_tran_locks`), login/host/app,
   and the blocked statement.
4. Note the head blocker's open-transaction age and what it is doing (or waiting
   on) — an idle-in-transaction head blocker is a common culprit.

## Output

A **blocking chain** table (head blocker first), then a one-paragraph summary
naming the head blocker and the most likely cause (long/idle transaction, a
missing index forcing long scans that hold locks, lock escalation, etc.).

## Recommend, don't act

- Suggest next steps: inspect the head blocker's transaction, add/adjust an index,
  shorten the transaction, or have an authorized DBA `KILL` **only after
  confirmation**.
- Never issue `KILL`, `ALTER`, or any modification yourself.
- If a DMV is blocked by permissions, say so (`VIEW SERVER STATE` is typically
  required) and suggest the read-only grant.
