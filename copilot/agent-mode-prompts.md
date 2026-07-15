# SSMS Copilot — Agent Mode prompts

Copy/paste these into **GitHub Copilot Agent Mode** in SSMS 22.7+ (preview). Agent
Mode can run multi-step investigations and propose actions, pausing for your
approval. Connect to the **WideWorldImporters** database on the SQL Server VM
first.

## Place in the story

- **Stage:** continue the same DBA investigation as a multi-step Agent exercise.
- **Enter from:** the [Ask mode explanation](ask-mode-prompts.md) and the raw
  Query Store regression report.
- **This document owns:** the full Agent mode prompts, approval behavior,
  execution context, and expected DBA review output.
- **Continue with:** the [database guidance](database-instructions.md),
  [skills guide](skills-demo-guide.md), the README
  [guardrail model](../README.md#guardrails-and-execution-identity), and the
  [reviewed-fix validation flow](../README.md#apply-the-reviewed-fix-and-validate).
- **For a live run:** use the condensed [one-page prompt sheet](ssms-demo-prompts.md)
  and return here for approval, context, and output details.

> Guardrails reminder: Approvals in Agent Mode are a convenience, **not** a
> security boundary. The connected login's SQL permissions are the real control.
> This demo installs a body-only constitution, so Copilot uses the account
> connected in SSMS. `GHCP_DB_User` illustrates a least-privilege permission set
> separately; it is not the default live execution identity. See
> [database-instructions.md](database-instructions.md) and approve only reviewed,
> read-only steps in this flow.

## How to use this stage

Ask Mode answers one question at a time. **Agent Mode** continues the same DBA
workflow from a goal ("investigate why this regressed") and runs a **chain** of
read-only steps — querying Query Store, comparing time windows, and assembling a
findings table — **pausing for your approval** before each step.

> **Core takeaway:** Agent Mode performs the same DBA workflow across several
> steps. It still asks for approval and cannot do anything the connected login is
> not permitted to do.

## Ask vs Agent — the one-line difference

- **Ask** = a conversation. It answers; you drive each step.
- **Agent** = a worker. It plans and executes multiple steps toward a goal, showing
  its work and asking you to **Approve** each action.

## How approvals look (what you'll click)

When Agent Mode wants to run SQL, an **approval prompt** shows the exact statement:

- Use **Allow once** for reviewed read-only steps (`SELECT ...` against
  `sys.query_store_*` and other DMVs) — that is the investigation.
- If it ever proposes a change (`CREATE/ALTER/DROP/UPDATE ...`), **don't approve it
  live** — that's your cue: *"here the DBA takes over and applies it manually in
  test."*
- Agent mode is `READ_ONLY` by default in SSMS, and this demo keeps the
  investigation read-only. Independently, the connected account's SQL permissions
  determine what SQL Server authorizes. Approvals are workflow; **permissions**
  are enforcement.

## Before you start
1. Confirm **WideWorldImporters** exists and Query Store is on (or run
   `scripts/sql/01-enable-query-store.sql`).
2. Open Copilot chat, switch the mode selector to **Agent**.
3. Include **WideWorldImporters** and the server in the prompt. Agent mode does
  not inherit the active query editor's connection automatically.
4. Keep `scripts/sql/09-query-store-regression-report.sql` open to cross-check.

## 1. Investigate the regression (read-only)
```
In the WideWorldImporters database on this server, investigate why query performance regressed after the latest workload run. Use Query Store where possible. Do not make any schema or data changes. Return findings as a DBA review table.
```

## 2. Compare baseline vs regressed windows
```
Compare the baseline and regressed workload windows in Query Store. Identify the top queries with increased duration, CPU, and logical reads. Include query_id, plan_id, likely cause, and recommended next action.
```

The demo uses separate `_Baseline` and `_Regressed` procedures. Pair them by
logical procedure family and report each phase's `query_id` and `plan_id` rather
than treating them as one Query Store identity.

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

## Expected output and DBA validation

- **1 — Investigate.** *Expect:* several approved read-only Query Store queries,
  then a DBA review table (query, `query_id`, `plan_id`, metric deltas, likely
  cause). *Control check:* Agent Mode should choose the relevant views from the
  stated goal and request approval before each action.
- **2 — Compare windows.** *Expect:* big increases in duration/CPU/logical reads
  and a **plan-shape difference (seek versus scan)** across the paired procedure
  variants. Each variant has its own `query_id` and `plan_id`. *Validation:* the
  AI summary and raw report (script 09) should agree because both use the same
  evidence. Ratios are often **10×–100×+**; the *relative* change matters, not an
  absolute benchmark.
- **3 — Analyze options.** *Expect:* it lands on **sargable rewrite + restore the
  index** as the simplest safe fix; plan forcing/hints/partitioning treated as
  heavier. *Decision point:* prefer the lowest-risk option supported by evidence.
- **4 — Remediation plan.** *Expect:* each option with risk, benefit, validation,
  and **rollback**. *Control check:* rollback must be a first-class step.
- **5 — Review-only T-SQL.** *Expect:* the fix as text (sargable proc +
  `CREATE INDEX` + `UPDATE STATISTICS`), not executed. *Control check:* Copilot
  drafts the change; the DBA reviews and applies it.
- **6 — Partitioning.** *Expect:* concludes partitioning is **not** justified here,
  pointing back to rewrite + index. *Decision point:* do not introduce
  partitioning when the simpler fix resolves the measured problem.

## Likely DBA questions

- **"Can it change my database?"** Agent mode can perform changes when write tools
  are enabled, the action is approved, and the execution identity has permission.
  This demo keeps the investigation read-only and applies the fix manually.
- **"So approvals are the security control?"** No — approvals are a workflow
  checkpoint; **SQL permissions** are the security control.
- **"Is Agent mode GA?"** Preview in SSMS 22.7+. The read-only investigation is the
  safe, compelling part to show.
- **"What if the analysis is wrong?"** Validate against the raw report (script 09)
  and re-run the workload after the fix (script 12).
- **"Does this work on-prem?"** Yes — only the connection target differs; SSMS +
  Copilot run from the DBA workstation/jump box.

## Going further

For harder problems (implicit conversion, parameter sniffing), ad-hoc NL-to-SQL, a
"catch the wrong answer" moment, and using an **MCP** tool to file a ticket from
Agent Mode, see [advanced-scenarios.md](advanced-scenarios.md) (optional Act 2).
