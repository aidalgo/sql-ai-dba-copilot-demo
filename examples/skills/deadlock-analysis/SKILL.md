---
name: deadlock-analysis
description: Analyze recent SQL Server deadlocks from the system_health Extended Events session. Use when asked about deadlocks, deadlock victims, or "why did my transaction get chosen as a deadlock victim".
---

# Deadlock analysis (system_health)

**Read-only.** SQL Server records deadlock graphs in the always-on `system_health`
Extended Events session — no setup needed.

## Steps

1. Read deadlock XML from `system_health` (via `sys.fn_xe_file_target_read_file`
   for `system_health*.xel`, or the ring-buffer target).
2. For each recent deadlock graph, extract:
   - the **victim** and the surviving process(es),
   - the objects / indexes and lock modes involved,
   - each process's statement and input buffer.
3. Identify the pattern (e.g. two procedures touching the same tables in opposite
   order; a key-lookup taking a range lock; ascending-key / last-page contention).

## Output

Per deadlock: victim, participants, resources, and a plain-language **why**. Then a
recommended fix — usually a consistent object access order, a covering index to
remove a lookup, shorter transactions, or an appropriate isolation level
(e.g. `READ COMMITTED SNAPSHOT`). **Recommend only.**

## Notes

- `system_health` is a rolling buffer — very old deadlocks may have aged out.
- Reading the XEvents file target needs `VIEW SERVER STATE`; note it if blocked.
