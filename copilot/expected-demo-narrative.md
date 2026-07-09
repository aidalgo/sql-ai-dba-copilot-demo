# Expected demo narrative (presenter script)

Use these talking points while you run the demo. They keep the focus on the DBA
workflow and the guardrails, not on "AI magic". Each line maps to a moment in the
flow described in the README.

## How to use this script (especially if you're not a DBA)

You don't need to read SQL or know SSMS deeply. You need to:
1. **Run the numbered scripts in order** (README §13–§23) — each prints `[OK]`.
2. **Paste the prompts** from `ask-mode-prompts.md` and `agent-mode-prompts.md`.
3. **Narrate** using the lines below.

It's one story: *a small code change broke a query's index usage; Query Store
proved it; Copilot helped read the evidence and draft the fix; the DBA applied it;
Query Store proved the fix worked.* If a hard question comes, fall back to the
matching **Core message**.

## Concept cheat sheet (so you can speak a DBA's language)

- **Index seek vs scan** — seek = jump to the rows you need (fast); scan = read the
  whole table (slow at 10M rows). The regression turns a seek into a scan.
- **Sargable** — a filter SQL Server can seek on. `YEAR(InvoiceDate) = 2015` is
  **not** sargable (function on the column → scan); a date **range** is.
- **Query Store** — SQL Server's flight recorder: saves plans + runtime stats
  (duration, CPU, logical reads, counts) over time. The demo's source of truth.
- **query_id / plan_id** — IDs Query Store assigns; a regression often shows a
  **new plan_id** for the same query_id (the plan changed).
- **The fix** — make the filter sargable **+** restore the dropped index **+**
  update statistics. Simple and safe.

## Core messages
- **"We start with Query Store as the source of truth."**
  Query Store recorded the before and after, so every claim is backed by captured
  runtime stats and plans — not anecdotes.

- **"Copilot is not replacing the DBA; it accelerates investigation."**
  The DBA still decides. Copilot summarizes Query Store, spots anti-patterns, and
  drafts options faster than clicking through DMVs by hand.

- **"Agent Mode can investigate across multiple steps, but approvals and SQL
  permissions remain the guardrails."**
  Agent Mode chains steps (read Query Store → compare windows → draft a plan), and
  you approve each action. The low-privilege login is what actually prevents
  changes.

- **"The first AI-generated answer is not the final answer; DBAs validate with
  Query Store, execution plans, and workload evidence."**
  Treat Copilot's output as a hypothesis. Confirm with the regression report, the
  graphical plan, and a re-run of the workload.

- **"Partitioning is evaluated with evidence, not blindly recommended."**
  The partitioning helper shows row counts, date distribution, and access pattern
  so the recommendation is justified — and here the real fix is the sargable
  rewrite plus the index, not partitioning.

- **"This maps to on-prem because SQL Server remains where it is; SSMS runs from
  the DBA workstation or jump server."**
  Nothing about the database changes. The same scripts and workflow apply to
  on-prem SQL Server 2019/2022; only the connection target differs.

## Beat-by-beat (do → say → expect → transition)

**0. Setup (before the audience):** deployment done, WideWorldImporters restored,
Query Store on, demo objects + ~10M rows loaded (README §11–§14); SSMS open and
connected to WideWorldImporters.

**1. Baseline — "healthy looks like this."**
- *Do:* run `scripts/sql/08-query-store-baseline-report.sql`.
- *Say:* "The query behaving well — fast, low logical reads, using a **seek**."
- *Next:* "Now a developer ships a 'harmless' change…"

**2. Introduce the regression.**
- *Do:* run `06-introduce-performance-issue.sql` (drops the index), then
  `07-run-regressed-workload.sql`.
- *Say:* "We dropped the supporting index and switched to a query that wraps the
  date in `YEAR()` — same result, but it can't seek anymore."
- *Next:* "Let's not guess — look at Query Store."

**3. Regression report — "the flight recorder caught it."**
- *Do:* run `09-query-store-regression-report.sql`.
- *Say:* "Duration, CPU, and logical reads jumped by a large factor, and the plan
  flipped from **seek to scan**. Evidence, not a hunch."
- *Expect:* big ratios (often 10×–100×+) and a new plan_id.
- *Next:* "Now bring in Copilot to read this like a DBA."

**4. Ask Mode — explain + rewrite.**
- *Do:* open `Demo.usp_GetRegionalSalesByYear_Regressed`; paste Ask prompts 1–3.
- *Say:* "It names the non-sargable predicate, proposes the date-range rewrite, and
  reads the plan in plain English — in seconds."
- *Next:* "Ask answers one question at a time. Let's give Agent Mode the goal."

**5. Agent Mode — multi-step investigation.**
- *Do:* switch to Agent; paste Agent prompts 1–2; **approve read-only steps**.
- *Say:* "It chains the steps and hands me a DBA review table — and it asked
  permission first. Approvals are workflow; **permissions** are security."
- *Next:* "It drafts a fix, but the human applies it."

**6. Apply the fix — manually.**
- *Do:* run the recommended parts of `10-apply-fix-options.sql` (recreate index +
  update stats) and use the `_Fixed` procedure.
- *Say:* "The DBA applies the change, controlled, with a rollback ready."
- *Next:* "Did it help? Back to Query Store."

**7. After-fix report — prove it.**
- *Do:* run `11-run-fixed-workload.sql`, then `12-query-store-after-fix-report.sql`.
- *Say:* "Duration and logical reads drop back, the **seek** is back, and
  `speedup_x` quantifies it. Loop closed."
- *Next:* "And this isn't a cloud trick…"

**8. Close — on-prem + guardrails.**
- *Say:* "Nothing about the database changed — same SQL Server, same scripts;
  Copilot ran from the workstation. The DBA stayed in control, and SQL permissions
  — not the AI — were the boundary."

## Likely audience questions (crisp answers)
- **"Is the AI changing production?"** No. Investigation is read-only; the fix is
  applied by the DBA, in test first, with rollback.
- **"What actually stops it writing?"** The connected login's SQL permissions
  (least-privilege). Approvals are just a workflow prompt.
- **"Did you rig the numbers?"** They come straight from Query Store; we run the
  same report the AI used so anyone can verify.
- **"Would this work on our on-prem 2019/2022?"** Yes — same workflow; only the
  connection target differs.
- **"What if Copilot is wrong?"** Treat it as a hypothesis; validate with Query
  Store, the plan, and a re-run. That discipline is the point.

## Logistics & tips
- **Time:** ~15–20 min. If short, do beats 1–5 and 7.
- **Reset between runs:** `scripts/sql/99-reset-demo.sql` (keeps WideWorldImporters
  intact).
- **If Copilot says "does not have support for this connection context":** the
  query window is on `master` — switch it to WideWorldImporters.
- **Keep the raw report open** next to Copilot and cross-check live — that contrast
  (AI summary vs raw evidence) is the most persuasive moment.

## Going further (optional Act 2)

If the room wants more, [advanced-scenarios.md](advanced-scenarios.md) layers on a
subtle implicit-conversion bug (and optional parameter sniffing), ad-hoc NL-to-SQL,
a "catch the wrong answer" trust moment, and Copilot filing a ticket via an MCP
tool — all after the main demo, with cleanup included.
