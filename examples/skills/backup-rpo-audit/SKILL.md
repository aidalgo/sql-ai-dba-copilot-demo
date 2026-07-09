---
name: backup-rpo-audit
description: Audit SQL Server backup history and flag recovery-point (RPO) gaps. Use when asked about backup status, last backup, RPO, or "are all databases backed up".
---

# Backup / RPO audit

**Read-only.** Reads backup history from `msdb`.

## Steps

1. For every online database (`sys.databases` where `state_desc = 'ONLINE'`), find
   the most recent **FULL** (`type = 'D'`), **DIFFERENTIAL** (`type = 'I'`), and
   **LOG** (`type = 'L'`) backup from `msdb.dbo.backupset` (join
   `msdb.dbo.backupmediafamily` for the path).
2. Consider the recovery model (`sys.databases.recovery_model_desc`): LOG backups
   only matter for `FULL` / `BULK_LOGGED` databases.
3. Flag:
   - any online DB with **no FULL in the last 24h**,
   - any `FULL`/`BULK_LOGGED` DB with **no LOG backup in the last ~60 min**,
   - any DB with **no backup at all**.

## Output

A table: database, recovery model, last full, last diff, last log, and an RPO
status (**OK / WARN / CRITICAL**) with the gap. Then a short summary of the worst
offenders.

## Recommend, don't act

- Suggest the missing backup schedule / job; on request, draft a `RESTORE`
  sequence (full → latest diff → log chain) to a point in time — for review.
- Never run `BACKUP` / `RESTORE` or change Agent jobs yourself.
