# SSMS Copilot — Agent Mode prompts

Copy/paste these into **GitHub Copilot Agent Mode** in SSMS 22.7+ (preview). Agent
Mode can run multi-step investigations and propose actions, pausing for your
approval. Connect to the **WideWorldImporters** database on the SQL Server VM
first.

> Guardrails reminder: Approvals in Agent Mode are a convenience, **not** a
> security boundary. The connected login's SQL permissions are the real control.
> For the demo, connect with the low-privilege investigation identity (see
> `copilot/ssms-database-constitution.md` and
> `scripts/sql/15-install-copilot-constitution.sql`) and approve only read-only
> steps at first.

## 1. Investigate the regression (read-only)
```
In the WideWorldImporters database on this server, investigate why query performance regressed after the latest workload run. Use Query Store where possible. Do not make any schema or data changes. Return findings as a DBA review table.
```

## 2. Compare baseline vs regressed windows
```
Compare the baseline and regressed workload windows in Query Store. Identify the top queries with increased duration, CPU, and logical reads. Include query_id, plan_id, likely cause, and recommended next action.
```

## 3. Analyze the worst query (no changes yet)
```
Analyze the worst regressed query. Consider query rewrite, indexing, statistics, plan forcing, Query Store hints, and partitioning. Do not implement anything yet.
```

## 4. Produce a remediation plan
```
Create a remediation plan with risk, expected benefit, validation steps, and rollback steps.
```

## 5. Generate review-only fix T-SQL
```
Generate the T-SQL I should review to apply the safest fix in a test environment. Do not execute it automatically.
```

## 6. Assess partitioning with evidence
```
Assess whether partitioning is justified for this workload. Use evidence from row counts, date distribution, access pattern, and maintenance needs.
```

---

### Suggested Agent Mode flow for the demo
1. Prompt **1** to investigate — approve only the read-only Query Store queries.
2. Prompt **2** to get the before/after comparison as a table (cross-check it
   against `scripts/sql/09-query-store-regression-report.sql`).
3. Prompt **3** to enumerate options without acting.
4. Prompt **4** for a structured remediation plan (risk / benefit / validate /
   rollback).
5. Prompt **5** to get review-only T-SQL — then **you** apply the fix manually via
   `scripts/sql/10-apply-fix-options.sql`.
6. Prompt **6** to show responsible partitioning analysis (it should recommend the
   query rewrite + index first, not partitioning).
