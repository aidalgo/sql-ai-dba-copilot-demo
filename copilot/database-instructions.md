# Database instructions and execution context

This guide explains the database-resident guidance installed for the demo, how
it relates to Agent skills, and where SQL Server enforces the actual security
boundary. It is the architectural reference for the root guide's
[guardrail and execution-identity model](../README.md#guardrails-and-execution-identity).

## Place in the story

- **Stage:** understand the control model behind the core Ask and Agent exercise.
- **Enter from:** the [Agent mode investigation](agent-mode-prompts.md), or the
  physical and logical architecture in the
  [main README](../README.md#workflow-and-control-model).
- **This document owns:** database instructions, execution context, precedence,
  and the demo's least-privilege model.
- **Continue with:** the [guardrail demonstration](../README.md#guardrails-and-execution-identity),
  then the [skills guide](skills-demo-guide.md) for reusable Agent runbooks.

## Architectural role

GitHub Copilot in SSMS can use two kinds of guidance in this repository:

| Guidance | Stored in | Applies to | Role |
| --- | --- | --- | --- |
| Database `CONSTITUTION.md` | Database-level extended property | Ask mode and Agent mode for the database | Highest-precedence database guidance and optional execution context |
| Object `AGENTS.md` | Extended property on a table, column, or procedure | Ask mode and Agent mode when the object is relevant | Local business meaning and object-specific usage guidance |
| Agent skill | Workspace or personal `SKILL.md` | Agent mode when its description matches | Reusable task procedure, such as reviewing a Query Store regression |

Instructions **guide behavior**. They do not grant access or replace SQL Server
permissions. Skills are separate from database instructions and require Agent
mode; see [skills-demo-guide.md](skills-demo-guide.md).

## Precedence

The database `CONSTITUTION.md` has the highest precedence for its database and
overrides object-level `AGENTS.md` instructions. Object instructions add local
context when they do not conflict with the constitution.

This is important for governance: a table or procedure instruction cannot weaken
a database-wide requirement such as evidence-first analysis or least privilege.

## What the demo installs

[scripts/sql/15-install-copilot-constitution.sql](../scripts/sql/15-install-copilot-constitution.sql)
is the executable source of truth. It installs:

1. A body-only database `CONSTITUTION.md` that directs Copilot to use Query Store,
   remain read-only during investigation, cite evidence, recommend the simplest
   safe fix, and include validation and rollback.
2. Object-level `AGENTS.md` properties for `Demo.LargeInvoiceFact` and the
   baseline, regressed, and fixed procedures.
3. `GHCP_DB_User`, a `WITHOUT LOGIN` database user with `SELECT` on the required
   schemas, `EXECUTE` on `Demo`, and `VIEW DATABASE STATE`.

The Markdown guide intentionally summarizes the installed text rather than
duplicating it verbatim. Review script 15 for the exact constitution and object
instructions that SQL Server stores.

## Current execution model

The installed constitution is **body-only**: it does not set
`agentExecuteAsUser`. Both Ask mode and Agent mode therefore execute generated
queries under the account used to connect SSMS.

`GHCP_DB_User` is an **illustrative permission model**. The README uses
`EXECUTE AS USER = 'GHCP_DB_User'` to demonstrate that reads succeed while DML
fails. That test proves how SQL Server permissions behave, but it does not switch
the live Copilot session to `GHCP_DB_User`.

| Control | What it does | What it does not do |
| --- | --- | --- |
| Database instructions | Shape generated analysis and recommendations | Enforce database authorization |
| Agent mode `READ_ONLY` default | Blocks write execution through the default tool configuration | Replace SQL permissions or change control |
| Agent approval | Confirms operator intent before a query or tool invocation | Grant permissions the execution identity does not have |
| SQL Server permissions | Enforce which objects and operations the identity can access | Decide whether a recommendation is operationally appropriate |
| DBA review | Owns the decision, test, rollback, and validation | Bypass the database security model |

## Demonstrate the permission boundary

Run the following as an account allowed to impersonate `GHCP_DB_User`:

```sql
EXECUTE AS USER = 'GHCP_DB_User';
SELECT TOP (1) * FROM Demo.LargeInvoiceFact;      -- allowed
UPDATE Demo.LargeInvoiceFact SET Quantity = 0;    -- denied
REVERT;
```

If the `UPDATE` is denied, SQL Server is enforcing the intended permission set.
The Agent approval interface is not part of that enforcement decision.

## Object guidance installed by the demo

The table instruction explains that `Demo.LargeInvoiceFact` is amplified demo
data and that date filters should use a sargable half-open range. Procedure
instructions distinguish intentionally regressed variants from healthy baseline
and fixed variants. Together they provide local meaning while the constitution
retains the database-wide operating rules.

Verify the installed properties with:

```sql
SELECT name,
       CONVERT(nvarchar(max), value) AS instruction
FROM sys.extended_properties
WHERE class = 0
  AND name = N'CONSTITUTION.md';

SELECT OBJECT_SCHEMA_NAME(major_id) AS schema_name,
       OBJECT_NAME(major_id) AS object_name,
       CONVERT(nvarchar(max), value) AS instruction
FROM sys.extended_properties
WHERE class = 1
  AND name = N'AGENTS.md';
```

## Optional fixed execution context

SSMS 22.7+ supports an `agentExecuteAsUser` property in the constitution's YAML
front matter:

```yaml
---
agentExecuteAsUser: <database user or SQL login>
---
```

Microsoft documents both a dedicated database user and a SQL login as supported
identity types. The connected account must have `IMPERSONATE` permission on the
designated identity. This repository leaves the property unset so that the demo
can explain the default execution model directly.

Some earlier SSMS builds or environments have produced connection-context errors
with a `WITHOUT LOGIN` database user. Treat that as a compatibility observation,
not a general product rule: test the exact SSMS build and authentication model
before selecting an execution identity.

## Design guidance for customer adoption

- Start with a dedicated, low-privilege identity and grant only the object access
  needed for investigation.
- Put database-wide governance in `CONSTITUTION.md`; use `AGENTS.md` for local
  business meaning that does not conflict with the constitution.
- Keep task procedures in Agent skills so the DBA team can review and version
  them independently.
- Test instructions and execution context in non-production before broader use.
- Audit permissions and instruction content as the database and operating model
  evolve.

## Product references

- [Database instructions](https://learn.microsoft.com/ssms/github-copilot/database-instructions)
- [Execution context](https://learn.microsoft.com/ssms/github-copilot/execution-context)
- [Agent mode](https://learn.microsoft.com/ssms/github-copilot/agent-mode)
- [Agent skills](https://learn.microsoft.com/ssms/github-copilot/agent-skills)
