# Expected demo narrative (presenter script)

Use these talking points while you run the demo. They keep the focus on the DBA
workflow and the guardrails, not on "AI magic". Each line maps to a moment in the
flow described in the README.

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

## Beat-by-beat
1. Show the **baseline** report — fast seeks, low reads.
2. Introduce the regression (drop index + non-sargable proc) and run the
   **regressed** workload.
3. Show the **regression** report — duration/CPU/reads up by a large factor,
   plan changed from seek to scan.
4. **Ask Mode**: open the regressed proc, have Copilot explain the bottleneck and
   propose a sargable rewrite.
5. **Agent Mode**: investigate with Query Store, approve read-only steps, get a
   DBA remediation table.
6. Apply the **fix** manually (rewrite + recreate index + update stats).
7. Run the **fixed** workload and show the **after-fix** report — back to (or
   better than) baseline.
8. Close on the **on-prem parallels** and **guardrails**.
