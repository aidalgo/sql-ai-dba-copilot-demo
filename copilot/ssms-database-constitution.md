# SSMS database instructions — CONSTITUTION.md (source of truth)

This repository's `.github/skills/*` files are **Agent skills** — task runbooks
that GitHub Copilot in SSMS (**22.7+, Agent Mode**) discovers automatically by
their `description`, either when the repo folder is open in SSMS or when you add
them as *personal* skills. (Beginner step-by-step: [skills-demo-guide.md](skills-demo-guide.md).)
They are **separate from** the **database instructions** covered here, which SQL
Server stores as **extended properties** on the database and its objects and
applies to both Ask and Agent mode whenever you connect — no repo folder required:

- A **database-level** extended property named **`CONSTITUTION.md`** — the
  highest-precedence instruction set for the whole database. Copilot loads it for
  both Ask and Agent mode when connected to this database.
- **Object-level** extended properties named **`AGENTS.md`** on tables, columns,
  and procedures (see [ssms-database-instructions.md](ssms-database-instructions.md)).

`scripts/sql/15-install-copilot-constitution.sql` installs the exact text below as
the `CONSTITUTION.md` extended property, creates the low-privilege investigation
user, and adds the object-level `AGENTS.md` properties.

## Execution identity and least privilege

By default the constitution is installed **body-only** — there is **no**
`agentExecuteAsUser` front matter. Copilot in SSMS has no separate permissions; it
runs generated SQL **under the login you connect SSMS with**, and SQL Server
permission enforcement (not Copilot, not the Agent Mode approval prompt) is the
security boundary. **The guardrail is simply to connect with a least-privilege
login.**

`scripts/sql/15-install-copilot-constitution.sql` creates **`GHCP_DB_User`** to
*model* such a principal. It is granted exactly:
- `SELECT` on the `Demo`, `Sales`, `Warehouse`, and `Application` schemas
- `VIEW DATABASE STATE` (required to read `sys.query_store_*` and other DMVs)
- `EXECUTE` on the `Demo` schema (so it can run the read-only demo procedures)

It is **not** granted INSERT/UPDATE/DELETE/ALTER/DROP/CREATE. You can demonstrate
the boundary directly:

```sql
EXECUTE AS USER = 'GHCP_DB_User';
SELECT TOP (1) * FROM Demo.LargeInvoiceFact;      -- allowed (read)
UPDATE Demo.LargeInvoiceFact SET Quantity = 0;    -- blocked: no permission
REVERT;
```

### Optional corner case: pin Copilot to a fixed identity (`agentExecuteAsUser`)

If you want Copilot to always run as **one fixed identity regardless of who is
connected**, add an `agentExecuteAsUser` value to the YAML front matter of the
constitution. SSMS then runs every Copilot query via `EXECUTE AS` for that
identity, and the signed-in login needs `IMPERSONATE` on it.

```yaml
---
agentExecuteAsUser: GHCP_Login

---
```

Use a **SQL login**, not a `WITHOUT LOGIN` database user: `EXECUTE AS USER` on a
database user yields a database-scoped token with no server context, which makes
Copilot fail to initialize (*"GitHub Copilot in SSMS does not have support for
this connection context"*). A low-privilege **login** keeps a server-scoped token
and initializes correctly. This is a corner case — for most demos, connecting with
a least-privilege login is simpler and is the recommended model. A commented
template is at the end of `scripts/sql/15-install-copilot-constitution.sql`.

---

## CONSTITUTION.md content (installed verbatim)

> The block below is what gets stored as the `CONSTITUTION.md` database extended
> property (installed **body-only**, without `agentExecuteAsUser` front matter).

```markdown
# Database constitution — AI-assisted DBA investigation (WideWorldImporters demo)

You are assisting a Database Administrator who is investigating SQL Server
performance using **Query Store as the source of truth**. Behave like a careful,
senior DBA.

## Operating principles
1. **Investigation is read-only by default.** Prefer querying Query Store views
   (`sys.query_store_query`, `sys.query_store_plan`, `sys.query_store_runtime_stats`,
   `sys.query_store_runtime_stats_interval`, `sys.query_store_query_text`) and
   other DMVs over guessing.
2. **Never modify data or schema unless the human explicitly asks for it in this
   session.** Do not run INSERT, UPDATE, DELETE, MERGE, TRUNCATE, CREATE, ALTER,
   DROP, or grant/revoke statements during investigation.
3. **Propose changes as reviewable T-SQL**, with: when to use it, the risk, how to
   validate it, and how to roll it back. Let the DBA execute it manually in a
   test environment first.
4. **Cite evidence.** Reference `query_id`, `plan_id`, time windows, and the
   runtime metrics (duration, CPU, logical reads, execution count, plan count)
   that support each conclusion.
5. **Diagnose root cause before recommending fixes.** Common causes here:
   non-sargable predicates (e.g. `YEAR(col) = @y`), missing/dropped indexes,
   stale statistics, and plan changes (seek → scan).
6. **Prefer the simplest safe fix:** make the predicate sargable and add/restore a
   supporting index before considering plan forcing, Query Store hints, or
   partitioning.
7. **Partitioning is not a generic tuning fix.** Only discuss it with evidence
   from row counts, date/range access patterns, retention/maintenance needs, and
   index alignment. Recommend simpler fixes first.
8. **Return findings as a DBA review table** when asked to investigate: query,
   query_id, plan_id, metric deltas, likely cause, recommended next action, risk,
   validation, rollback.

## Hard guardrails
- You run under the connected DBA login, which should be a least-privilege
  principal. If an action is blocked by permissions, report it and suggest the
  manual step — do not attempt to escalate privileges.
- Approvals in Agent Mode are not a security boundary; SQL permissions are.
- This is a non-production demo database. Still, treat every recommendation as if
  it were going to production: review, test, validate, and keep a rollback.
```
