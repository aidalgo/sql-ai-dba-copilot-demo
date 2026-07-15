# GitHub Copilot DBA customizations

This directory is the single home for the repository's file-based Copilot
customizations. The two subdirectories use supported workspace discovery paths,
but target different hosts:

| Location | Host | What it contains |
| --- | --- | --- |
| `.github/skills/` | SSMS Agent mode | Seven intent-activated DBA runbooks in `SKILL.md` files |
| `.github/agents/` | VS Code | Three named custom agents in `*.agent.md` files |

SSMS provides built-in Ask and Agent modes. It discovers the skills, but does not
load the VS Code custom agents. VS Code discovers the custom agents from its
agent selector. Keeping both under `.github` gives the team one catalog without
blurring those product boundaries.

## SSMS Agent skills

All seven skills are active when this repository is open as the SSMS workspace.
Their descriptions are intentionally distinct so Copilot can select the relevant
runbook from the DBA's request.

| Skill | Use when | Expected output | Safety boundary |
| --- | --- | --- | --- |
| [query-store-regression-review](skills/query-store-regression-review/SKILL.md) | Comparing baseline and regressed Query Store windows | DBA review table with phase-specific query and plan IDs, deltas, cause, action, risk, validation, and rollback | Read-only runbook; connected identity permissions enforce access |
| [index-recommendation-validation](skills/index-recommendation-validation/SKILL.md) | Reviewing `CREATE INDEX` or missing-index suggestions | Create, modify, reject, or needs-more-evidence verdict | Recommendation only; the DBA reviews and applies any DDL |
| [partitioning-assessment](skills/partitioning-assessment/SKILL.md) | Deciding whether table partitioning is justified | Recommend, do-not-partition, or needs-more-evidence decision | Evidence gate; no partitioning changes are executed |
| [blocking-chain-triage](skills/blocking-chain-triage/SKILL.md) | Sessions are blocked or waiting on locks | Head blocker and blocking-chain table with next diagnostics | Never kills a session or changes state |
| [wait-stats-triage](skills/wait-stats-triage/SKILL.md) | Identifying where instance time is being spent | Ranked non-benign waits with interpretation and next checks | Reads cumulative wait statistics only |
| [deadlock-analysis](skills/deadlock-analysis/SKILL.md) | Investigating deadlock victims and resources | Victim, participants, resources, cause, and remediation options | Reads `system_health`; recommends only |
| [backup-rpo-audit](skills/backup-rpo-audit/SKILL.md) | Checking backup recency and recovery-point gaps | Per-database full, differential, and log status with RPO classification | Reads `msdb` history; never runs backup or restore |

To verify discovery in SSMS:

1. Open the repository root as the SSMS workspace.
2. Open Copilot Chat, select **Agent**, then open **Tools > Skills**.
3. Confirm all seven names appear without diagnostics.
4. Ask a matching question and confirm the activated skill name appears in chat.

The [SSMS Agent skills guide](../copilot/skills-demo-guide.md) provides the full
walkthrough and example prompts.

## VS Code custom agents

These agents are active workspace customizations in VS Code. Their MSSQL tool
names are illustrative and must match the installed extension. A query-capable
tool does not make an agent read-only; use a SQL identity whose permissions
enforce the intended boundary.

| Agent | Use when | Expected output | Tool boundary |
| --- | --- | --- | --- |
| [dba-read-only-investigator](agents/dba-read-only-investigator.agent.md) | Performing evidence-first incident triage | Ranked hypotheses, queries run, evidence, and human-applied next steps | Query and plan tools only; SQL permissions enforce read-only access |
| [dba-performance-tuner](agents/dba-performance-tuner.agent.md) | Reviewing plans, Query Store, rewrites, and index options | Root cause, rewrite, index trade-offs, validation, and rollback | Proposes changes; does not apply them |
| [dba-schema-change-reviewer](agents/dba-schema-change-reviewer.agent.md) | Reviewing DDL and migration scripts before deployment | Pass, concern, or blocker verdicts with safer alternatives | Review tools only; no deployment tools attached |

## Adoption sequence

1. Start with one task whose trigger and expected output are clear.
2. Review the skill or agent with the DBA team and adapt permissions, DMV
   requirements, thresholds, naming, and escalation rules.
3. Test discovery, activation, and output in nonproduction.
4. Confirm missing permissions are reported rather than bypassed.
5. Version changes as operational runbooks and review them like code.

## Design rules

- **Evidence first:** cite Query Store, plans, DMVs, time windows, and identifiers
  before drawing a conclusion.
- **Recommend before changing:** include risk, validation, and rollback; let the
  DBA own execution.
- **Separate behavior from enforcement:** instructions and tool lists guide
  behavior, while SQL Server permissions enforce access.
- **Keep descriptions specific:** the description is the discovery surface for a
  skill or agent.
- **Declare prerequisites:** instance diagnostics and `msdb` history can require
  permissions beyond ordinary database access.

Return to the [main learning guide](../README.md#customize-and-extend-copilot) to
use these customizations in the complete SSMS workflow.
