# Demo guide: GitHub Copilot **Agent skills** in SSMS

A beginner-friendly, click-by-click guide to showing Copilot **skills** in SQL
Server Management Studio. No prior SSMS or DBA experience needed to *present* it.

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
|---|---|---|---|---|---|
| **Database instructions** — `CONSTITUTION.md` / `AGENTS.md` | Rules stored **inside the database** (extended properties); highest precedence for that DB, and can pin Copilot's execution identity | The SQL database itself | One database | Ask **and** Agent, for **everyone** who connects | DB-specific business rules, data definitions, and guardrails that must travel with the data |
| **Custom instructions** | Standing preferences added to every matching request | A custom-instructions file in your repo root or user profile | Your project / user | Ask, Agent, completions | Team **conventions** (T-SQL style, sargable predicates, explicit column lists) |
| **Skills** — `SKILL.md` | A **task runbook** Copilot auto-discovers by its `description` and applies when relevant | `.github/skills/` (workspace) or your user profile | Repo or user | **Agent Mode** (on match) | Reusable **procedures** ("how we triage wait stats / validate an index") |
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

**Precedence:** the database **constitution** wins for its database and overrides
object-level `AGENTS.md`; custom instructions and skills layer context on top, and
a skill only activates when its `description` matches your request.

## What you need

- **SSMS 22.7 or later** with GitHub Copilot (AI Assistance) installed and signed in.
- **Agent Mode** — skills are used **only** in Agent Mode (Ask Mode ignores them).
  Agent Mode is currently in preview.
- For the SQL examples: connected to **WideWorldImporters**.

## The one idea to understand: *where skills live*

Copilot looks for skills in **two** places:

1. **Personal skills** — stored in your Windows **user profile**. Always available,
   in every session, no project needed. **This is the easiest path.**
2. **Workspace skills** — stored in a **folder/repo** at `.github/skills/`.
   Available when that folder is **open in SSMS**. This repo already ships three.

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

## Method B: use the three skills already in this repo

This repo ships three DBA skills under `.github/skills/`:
`query-store-regression-review`, `index-recommendation-validation`, and
`partitioning-assessment`. To have SSMS discover them:

1. Make sure the repo folder (`sql-ai-dba-copilot-demo`) is **on the jumpbox**
   (clone it with Git, or copy the folder over).
2. **Open the folder in SSMS** as your workspace (the "Open Folder" idea from
   above). If your SSMS build has no Open Folder option, use **Method A** instead
   and recreate each skill as a personal skill by pasting the contents of its
   `SKILL.md`.
3. Open Copilot Chat → switch to **Agent** → **Tools** → **Skills** panel. The
   three skills should be listed.
4. Trigger each by asking a matching question and watch its name light up:
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

## What to say to the room

- "A skill is a runbook the team writes **once**; Copilot picks the right one
  automatically from its description — no need to re-type a long prompt."
- "See the skill name light up? That's Copilot applying **our** standard procedure,
  consistently, instead of improvising."
- "Skills are portable and shareable across the team; database instructions
  (`CONSTITUTION.md`) live in the database. Together they make Copilot behave like
  *our* DBA team."

## Skill ideas worth exploring

Ideas only — *not* skills to build right now. Each would be one `SKILL.md` (a name,
a keyword-rich `description`, and a short **read-only** runbook). The repo already
ships `query-store-regression-review`, `index-recommendation-validation`, and
`partitioning-assessment`; here's where a DBA team might go next:

**Performance & plans**
- `blocking-chain-triage` — find the head blocker and the blocked sessions/queries.
- `deadlock-analysis` — read `system_health` deadlocks; summarize victims, resources, likely fix.
- `parameter-sniffing-check` — spot parameter-sensitive plans and lay out fix options.
- `tempdb-contention-check` — top tempdb consumers and PFS/GAM allocation contention.
- `missing-index-review` — evaluate missing-index DMV suggestions critically (not blindly).

**Availability & recovery**
- `always-on-health-check` — AG replica sync health; flag growing redo / log-send queues.
- `backup-rpo-audit` — last full/diff/log per database; flag RPO gaps.
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

> Keep every skill **read-only and evidence-first** — query the DMVs, cite the
> numbers, and *recommend* rather than change state. That's what makes them safe to
> let Copilot discover and apply automatically.

## Caveats

- **SSMS 22.7+**, **Agent Mode** only (Ask Mode doesn't use skills; Agent Mode is
  preview).
- Copilot decides what to activate from the **`description`** — vague descriptions
  won't trigger.
- Skill **names**: lowercase letters, numbers, hyphens; `name` must match the
  folder name.
- **Personal** skills are always available; **workspace** skills only when that
  folder is open in SSMS.
