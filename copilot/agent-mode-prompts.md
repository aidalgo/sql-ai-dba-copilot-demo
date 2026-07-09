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

## If you're presenting this and you're *not* a DBA

Ask Mode answers one question at a time. **Agent Mode** is the upgrade: you give it
a goal ("investigate why this regressed") and it runs a **chain** of read-only
steps by itself — querying Query Store, comparing time windows, assembling a
findings table — **pausing for your approval** before each step.

Your story:
> "Same DBA workflow, but Agent Mode does the legwork across several steps. It
> still asks permission, and it still can't do anything the connected login isn't
> allowed to do."

## Ask vs Agent — the one-line difference

- **Ask** = a conversation. It answers; you drive each step.
- **Agent** = a worker. It plans and executes multiple steps toward a goal, showing
  its work and asking you to **Approve** each action.

## How approvals look (what you'll click)

When Agent Mode wants to run SQL, an **approval prompt** shows the exact statement:

- **Approve** read-only steps (`SELECT ...` against `sys.query_store_*` and other
  DMVs) — that's the investigation.
- If it ever proposes a change (`CREATE/ALTER/DROP/UPDATE ...`), **don't approve it
  live** — that's your cue: *"here the DBA takes over and applies it manually in
  test."*
- Even if you *did* approve a change, the **least-privilege login would still block
  it**. Approvals are workflow; **permissions** are security.

## Before you start
1. Confirm **WideWorldImporters** exists and Query Store is on (or run
   `scripts/sql/01-enable-query-store.sql`).
2. Open Copilot chat, switch the mode selector to **Agent**.
3. Confirm the chat's database context is **WideWorldImporters** (not `master`).
4. Keep `scripts/sql/09-query-store-regression-report.sql` open to cross-check.

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

## What each prompt should produce (and what to say)

- **1 — Investigate.** *Expect:* several approved read-only Query Store queries,
  then a DBA review table (query, `query_id`, `plan_id`, metric deltas, likely
  cause). *Say:* "I gave it a goal, not steps — watch it choose the views and ask
  before each."
- **2 — Compare windows.** *Expect:* big increases in duration/CPU/logical reads
  and a **plan change (seek → scan)**. *Say:* "The AI summary and the raw report
  (script 09) agree — evidence, not vibes." Ratios are often **10×–100×+**; stress
  it's the *relative* change that matters, not an absolute benchmark.
- **3 — Analyze options.** *Expect:* it lands on **sargable rewrite + restore the
  index** as the simplest safe fix; plan forcing/hints/partitioning treated as
  heavier. *Say:* "It knows the whole toolbox but recommends the least-risky fix."
- **4 — Remediation plan.** *Expect:* each option with risk, benefit, validation,
  and **rollback**. *Say:* "Rollback is a first-class step — that's production
  thinking."
- **5 — Review-only T-SQL.** *Expect:* the fix as text (sargable proc +
  `CREATE INDEX` + `UPDATE STATISTICS`), not executed. *Say:* "The AI drafted it;
  the human applies it."
- **6 — Partitioning.** *Expect:* concludes partitioning is **not** justified here,
  pointing back to rewrite + index. *Say:* "It won't reach for the fancy tool when
  the simple fix wins."

## Likely questions from a DBA audience (crisp answers)

- **"Can it change my database?"** Only if it proposes a change, you approve it,
  *and* the connected login has permission. We keep it read-only and least-priv.
- **"So approvals are the security control?"** No — approvals are a workflow
  checkpoint; **SQL permissions** are the security control.
- **"Is Agent Mode GA?"** Preview in SSMS 22.7+. The read-only investigation is the
  safe, compelling part to show.
- **"What if the analysis is wrong?"** Validate against the raw report (script 09)
  and re-run the workload after the fix (script 12).
- **"Does this work on-prem?"** Yes — only the connection target differs; SSMS +
  Copilot run from the DBA workstation/jump box.
