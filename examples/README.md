# Examples: DBA skills & agents (templates)

Ready-to-adapt **example** Copilot customizations for SQL Server DBA work. They
live here (outside `.github/`) **on purpose** so they are *not* auto-discovered —
treat this as a catalog to copy from.

## What's here

```text
examples/
  skills/   # Agent SKILL.md runbooks (discovered ONLY under .github/skills/ or as personal skills)
  agents/   # VS Code custom agents (*.agent.md) — a persona + a scoped tool set
```

### Skills (`examples/skills/*/SKILL.md`)
- `blocking-chain-triage` — who is blocking whom, right now.
- `wait-stats-triage` — where the instance is spending its time.
- `deadlock-analysis` — read recent deadlocks from `system_health`.
- `backup-rpo-audit` — last full/diff/log per database + RPO gaps.

### Agents (`examples/agents/*.agent.md`)
- `dba-read-only-investigator` — safe production triage; **no** write tools attached.
- `dba-performance-tuner` — plan / Query Store tuning; proposes fixes only.
- `dba-schema-change-reviewer` — reviews DDL / migration scripts for risk.

## How to use them

**A skill** — copy its folder into `.github/skills/` in a repo you open in SSMS
(**22.7+, Agent Mode**), or add it as a *personal* skill via the Skills panel.
Copilot then discovers it automatically by its `description`. Step-by-step:
[../copilot/skills-demo-guide.md](../copilot/skills-demo-guide.md).

**An agent** — custom agents are a **VS Code** feature (with the MSSQL extension),
**not** SSMS. Copy the `*.agent.md` into your VS Code agents location and pick it
from the agent selector.

## Design rules (why these are safe)

- **Read-only, evidence-first:** query DMVs / Query Store, cite the numbers, and
  *recommend* — don't change state.
- **Guardrail by construction (agents):** the read-only agent simply has **no
  write/edit tools attached** — the omission *is* the control.
- **Tool names vary:** the `tools:` lists in the agents are illustrative; adjust
  them to match your installed MSSQL extension version.
- **Not a security boundary:** pair these with a **least-privilege login** — SQL
  Server permissions are the real control.
