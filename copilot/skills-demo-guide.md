# Demo guide: GitHub Copilot **Agent skills** in SSMS

A beginner-friendly, click-by-click guide to learning and testing Copilot
**skills** in SQL Server Management Studio.

## Place in the story

- **Stage:** understand how team-owned runbooks extend the core Agent exercise.
- **Enter from:** the [Agent mode investigation](agent-mode-prompts.md), after
  seeing the multi-step workflow once.
- **This document owns:** skill concepts, discovery locations, creation, and
  activation evidence.
- **Continue with:** the [database-instructions guide](database-instructions.md)
  for database-resident guidance, the seven
  [active workspace skills](../.github/README.md#ssms-agent-skills), and the
  [README remediation and validation flow](../README.md#apply-the-reviewed-fix-and-validate).
  After completing the core exercise, use the
  [custom-agent catalog](../.github/README.md#vs-code-custom-agents) for broader
  team adoption.

## What a "skill" is (in one minute)

A **skill** is a small Markdown file (`SKILL.md`) that gives Copilot a reusable
**runbook** for one kind of task — e.g. "how we triage wait stats" or "how we
validate an index." You write it **once**; then, in **Agent Mode**, Copilot
notices when your question matches the skill's *description* and follows it
automatically. It's the difference between re-typing a long prompt every time and
having a saved, shareable, consistent procedure.

Skills are one of several ways to shape Copilot — the next section lays out how
they differ from the constitution, custom instructions, and "custom agents."

## Constitution vs custom instructions vs skills (vs custom agents)

All of these steer Copilot and can be used **together**, but they live in different
places and do different jobs:

| Layer | What it is | Where it lives | Scope | Applies in | Best for |
| --- | --- | --- | --- | --- | --- |
| **Database constitution** — `CONSTITUTION.md` | Highest-precedence guidance stored as a database extended property; can also specify Copilot's execution identity | The SQL database itself | One database | Ask **and** Agent, for **everyone** who connects | Database-wide governance, coding rules, and execution context |
| **Object instructions** — `AGENTS.md` | Local context stored as an extended property on a table, column, or procedure | The SQL database object | One object | Ask **and** Agent when the object is relevant | Business meaning and object-specific usage guidance that does not conflict with the constitution |
| **Custom instructions** | Standing preferences added to every matching request | A custom-instructions file in your repo root or user profile | Your project / user | Ask, Agent, completions | Team **conventions** (T-SQL style, sargable predicates, explicit column lists) |
| **Skills** — `SKILL.md` | A **task runbook** Copilot auto-discovers by its `description` and applies when relevant | A supported workspace or personal skills directory | Repo or user | **Agent mode** (on match) | Reusable **procedures** ("how we triage wait stats / validate an index") |
| **Custom agents** | A named assistant persona with its own instructions + allowed tools that you pick | `*.agent.md` (a **VS Code** feature) | Your VS Code project | The agent you select | Specialized VS Code workflows |

**Rules of thumb**
- **Constitution** = *rules that belong to the database* — they travel with it,
  apply to everyone, and win ties. A DBA / `db_owner` sets them in SQL.
- **Custom instructions** = *how I always want answers written* (general, always on).
- **Skills** = *a saved procedure for one task* — focused, and only fires when the
  question matches the skill's `description`.
- **Custom agents** = a **VS Code** concept. **SSMS has no user-defined custom
  agents** — it gives you the built-in **Ask** and **Agent** modes, which you shape
  with the three layers above. (If you've seen `*.agent.md` "custom agents," that's
  the VS Code Copilot experience, not SSMS.)

**Precedence:** the database **constitution** has the highest precedence for its
database and overrides object-level `AGENTS.md`. Other customization layers add
context; a skill activates only in Agent mode when its `description` matches the
request. Guidance shapes behavior, while SQL Server permissions enforce access.

## What you need

- **SSMS 22.7 or later** with GitHub Copilot (AI Assistance) installed and signed in.
- **Agent Mode** — skills are used **only** in Agent Mode (Ask Mode ignores them).
  Agent Mode is currently in preview.
- For the SQL examples: connected to **WideWorldImporters**.

## The one idea to understand: where skills live

Copilot supports two **scopes** for skills:

1. **Personal skills** — stored in your user profile under `~/.copilot/skills/`,
  `~/.claude/skills/`, or `~/.agents/skills/`. They are available across
  projects for that user. **This is the easiest demo path.**
2. **Workspace skills** — stored in a repository under `.github/skills/`,
  `.claude/skills/`, or `.agents/skills/`. They are shared through source control
  and available when the repository is open as the SSMS workspace. This repo
  uses `.github/skills/` and already ships seven.

> **"Open a workspace/folder in SSMS"** simply means pointing SSMS at a folder on
> disk (like this repo's `sql-ai-dba-copilot-demo` folder) as your current project,
> so Copilot can see the files inside it — including `.github/skills/`. It's the
> same idea as "Open Folder" in VS Code. If your SSMS build doesn't offer an
> "Open Folder" option, **don't worry — use Method A below**, which needs no folder
> at all.

---

## Method A (recommended): create and demo a *personal* skill

This doubles as a great live demo — you codify a DBA runbook on the spot, with no
folder setup.

1. Click the **Copilot** badge at the **top-right** of SSMS to open the Copilot
   Chat pane.
2. At the top of the chat, switch the mode selector from **Ask** to **Agent**.
3. In the chat, click the **Tools** icon, then open the **Skills** panel.
4. Click the **+** button. When asked for scope, choose **Personal** (stored in
   your user profile).
5. Enter a name using **lowercase letters, numbers, and hyphens only** — e.g.
   `wait-stats-triage`. SSMS creates a `SKILL.md` template and opens it in the
   editor.
6. Replace the template body with a simple runbook. For example:
   ```
   ---
   name: wait-stats-triage
   description: Triage SQL Server wait statistics. Use when asked what the instance is waiting on, the top waits, or where time is being spent.
   ---
   # Wait-stats triage
   - Query sys.dm_os_wait_stats and exclude benign waits (CHECKPOINT_QUEUE, XE_TIMER, sleep/broker waits, etc.).
   - Return the top 10 by wait_time_ms, each with a one-line "what to check next".
   - Read-only only. Never change server settings.
   ```
   The **`name`** must match the skill's folder name. The **`description`** is what
   Copilot matches your question against — keep it specific and keyword-rich, or
   the skill won't fire.
7. **Save** the file. It now appears in the **Skills** panel.
8. In the chat (still **Agent Mode**), ask a matching question:
   ```
   What is this instance waiting on the most, and what should I look at next?
   ```
   Watch the **skill's name appear in the chat** for that answer — that's your proof
   Copilot activated the skill and followed your runbook (not improvising).

---

## Method B: use the seven skills already in this repo

This repo ships seven DBA skills under `.github/skills/`. Three support the core
performance exercise, and four cover blocking, waits, deadlocks, and backup RPO.
See the [customization catalog](../.github/README.md#ssms-agent-skills) for the
complete list. To have SSMS discover them:

1. Make sure the repo folder (`sql-ai-dba-copilot-demo`) is **on the jumpbox**
   (clone it with Git, or copy the folder over).
2. **Open the folder in SSMS** as your workspace (the "Open Folder" idea from
   above). If your SSMS build has no Open Folder option, use **Method A** instead
   and recreate each skill as a personal skill by pasting the contents of its
   `SKILL.md`.
3. Open Copilot Chat → switch to **Agent** → **Tools** → **Skills** panel. The
  seven skills should be listed.
4. Trigger the three core skills by asking a matching question and watch the
  selected name light up:
   - `Investigate this Query Store regression and give me a DBA review table.`
     → **query-store-regression-review**
   - `Should we create this index? CREATE INDEX ... (paste one)`
     → **index-recommendation-validation**
   - `Should we partition this table to fix the slow date queries?`
     → **partitioning-assessment**

---

## How to prove a skill is actually being used

- The activated skill's **name shows up in the chat** for that turn.
- The **Skills** panel lists every skill Copilot discovered (and flags any config
  errors via diagnostics).
- Ask `Show me the query you ran` to confirm the answer followed the skill's steps.

## Core learning points

- A skill is a runbook the team writes **once**. Copilot selects it from its
  description, so the DBA does not need to repeat a long prompt.
- The activated skill name in chat confirms that Copilot is applying the team's
  standard procedure instead of improvising an investigation path.
- Skills are portable and shareable across the team; database instructions
  (`CONSTITUTION.md`) live in the database. Together they align Copilot with the
  DBA team's operating practices.

## Additional skill ideas

Ideas only — *not* skills to build right now. Each would be one `SKILL.md` (a name,
a keyword-rich `description`, and a short **read-only** runbook). The repository
already ships the [seven active skills](../.github/README.md#ssms-agent-skills);
these are possible next additions:

**Performance & plans**
- `parameter-sniffing-check` — spot parameter-sensitive plans and lay out fix options.
- `tempdb-contention-check` — top tempdb consumers and PFS/GAM allocation contention.
- `missing-index-review` — evaluate missing-index DMV suggestions critically (not blindly).

**Availability & recovery**
- `always-on-health-check` — AG replica sync health; flag growing redo / log-send queues.
- `restore-plan-builder` — assemble the full → diff → log restore sequence to a point in time.

**Security & compliance**
- `permission-audit` — high-privilege principals, role membership, orphaned users.
- `login-hygiene` — sysadmin membership, disabled/expired logins, password policy.
- `sensitive-data-access-review` — who can read the PII / finance schemas.

**Capacity & maintenance**
- `file-growth-forecast` — file sizes, free space, autogrowth, and drive runway.
- `index-maintenance-advisor` — fragmentation-based rebuild/reorg advice, with thresholds.
- `statistics-freshness-check` — find stale statistics worth updating.

**Migration & ops**
- `azure-sql-migration-check` — features that block Azure SQL DB (cross-db refs, Agent jobs, unsupported features).
- `agent-job-failure-triage` — failed / long-running / disabled Agent jobs from `msdb`.
- `tsql-style-guide` — enforce sargable predicates, explicit column lists, schema-qualified names.

> Keep investigation skills **read-only and evidence-first**: query the DMVs, cite
> the numbers, and recommend rather than change state. This constrains the runbook,
> but it is not an authorization boundary; pair it with least-privilege SQL access.

## Caveats

- **SSMS 22.7+**, **Agent Mode** only (Ask Mode doesn't use skills; Agent Mode is
  preview).
- Copilot decides what to activate from the **`description`** — vague descriptions
  won't trigger.
- Skill **names**: lowercase letters, numbers, hyphens; `name` must match the
  folder name.
- **Personal** skills are always available; **workspace** skills only when that
  folder is open in SSMS.

## Product reference

See [Agent skills in SSMS](https://learn.microsoft.com/ssms/github-copilot/agent-skills)
for current locations, front matter, activation behavior, and product limits.
