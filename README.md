# SQL Server + GitHub Copilot AI DBA Demo (`sql-ai-dba-copilot-demo`)

A complete, reproducible demo that shows how a **DBA** can use **SQL Server
Management Studio (SSMS) with GitHub Copilot and Agent Mode** to investigate a
**performance regression**, use **Query Store as the source of truth**, analyze a
slow query, evaluate remediation options (query rewrite, indexing, statistics,
Query Store hints, plan forcing, partitioning assessment), and **validate the
impact of a fix** — all against Microsoft's **WideWorldImporters** sample
database.

> This is **not** a production solution. It is a safe, self-contained demo you can
> reproduce in Azure, with clear notes on how the same workflow applies to on-prem
> SQL Server 2019/2022.

---

## Table of contents
1. [Demo purpose](#1-demo-purpose)
2. [Architecture](#2-architecture)
3. [What this demo proves](#3-what-this-demo-proves)
4. [What this demo does not prove](#4-what-this-demo-does-not-prove)
5. [Prerequisites](#5-prerequisites)
6. [Azure deployment steps](#6-azure-deployment-steps)
7. [Connecting to the jumpbox](#7-connecting-to-the-jumpbox)
8. [Installing or validating SSMS with GitHub Copilot](#8-installing-or-validating-ssms-with-github-copilot)
9. [Signing into GitHub Copilot in SSMS](#9-signing-into-github-copilot-in-ssms)
10. [Connecting from SSMS to the SQL Server VM](#10-connecting-from-ssms-to-the-sql-server-vm)
11. [Downloading / restoring WideWorldImporters](#11-downloading--restoring-wideworldimporters)
12. [Enabling Query Store](#12-enabling-query-store)
13. [Running setup scripts manually in SSMS](#13-running-setup-scripts-manually-in-ssms)
14. [Running the baseline workload](#14-running-the-baseline-workload)
15. [Introducing the performance issue](#15-introducing-the-performance-issue)
16. [Running the regressed workload](#16-running-the-regressed-workload)
17. [Using the Query Store reports](#17-using-the-query-store-reports)
18. [SSMS Ask Mode demo flow](#18-ssms-ask-mode-demo-flow)
19. [SSMS Agent Mode demo flow](#19-ssms-agent-mode-demo-flow)
20. [Prompts to copy/paste into SSMS Copilot](#20-prompts-to-copypaste-into-ssms-copilot)
21. [How to show human approval and guardrails](#21-how-to-show-human-approval-and-guardrails)
22. [Applying a safe fix](#22-applying-a-safe-fix)
23. [Showing before/after improvement](#23-showing-beforeafter-improvement)
24. [Partitioning assessment discussion](#24-partitioning-assessment-discussion)
25. [Resetting the demo](#25-resetting-the-demo)
26. [Troubleshooting](#26-troubleshooting)
27. [Cleanup](#27-cleanup)
28. [On-prem parallels and customer notes](#28-on-prem-parallels-and-customer-notes)

Appendices: [Manual SSMS demo flow (24 steps)](#appendix-a--manual-ssms-demo-flow-24-steps) ·
[Security and guardrails](#appendix-b--security-and-guardrails) ·
[Repository layout](#appendix-c--repository-layout) ·
[Acceptance criteria](#appendix-d--acceptance-criteria)

---

## 1. Demo purpose

Show, end-to-end, how a DBA accelerates a real performance investigation with
GitHub Copilot in SSMS — **without** handing over control. Query Store provides
the evidence; Copilot helps read it, explain the slow query, and propose
remediation options; the DBA reviews, tests, and applies the fix manually; Query
Store proves the improvement.

The narrative (see [copilot/expected-demo-narrative.md](copilot/expected-demo-narrative.md)):
- We start with **Query Store as the source of truth**.
- Copilot is **not replacing the DBA**; it accelerates investigation.
- **Agent Mode** can investigate across multiple steps, but **approvals and SQL
  permissions remain the guardrails**.
- The **first AI answer is not the final answer**; DBAs validate with Query Store,
  execution plans, and workload evidence.
- **Partitioning is evaluated with evidence**, not blindly recommended.
- This **maps to on-prem**: SQL Server stays where it is; SSMS runs from the DBA
  workstation or jump server.

## 2. Architecture

```text
   Azure Resource Group
   +-----------------------------------------------------------------+
   |  Virtual Network (10.20.0.0/16)                                 |
   |                                                                 |
   |   subnet: jumpbox (10.20.1.0/24)     subnet: sql (10.20.2.0/24) |
   |   +-------------------------+        +------------------------+ |
   |   | Windows jumpbox VM      |  1433  | SQL Server 2022 VM     | |
   |   | - RDP (from your IP)    |------->| - Windows Server 2022  | |
   |   | - SSMS + Copilot        | private| - SQL 2022 Standard    | |
   |   | - runs the demo scripts |        | - NOT publicly exposed | |
   |   +-------------------------+        +------------------------+ |
   |         ^ RDP 3389 (NSG: allowedRdpSourceIp only)               |
   +---------|-------------------------------------------------------+
             |
        Your workstation (RDP)
```

- **Jumpbox VM** = the customer's existing DBA/admin jump server. SSMS + Copilot
  run **here**, not on the database server.
- **SQL Server VM** = the customer's on-prem SQL Server 2019/2022 estate.
- The SQL VM accepts SQL (1433) connectivity **only from the jumpbox subnet**;
  RDP to the jumpbox is restricted to a single source IP you provide.

Defined in [infra/main.bicep](infra/main.bicep).

## 3. What this demo proves

- A DBA can use **Query Store** to detect and quantify a regression
  (duration, CPU, logical reads, execution count, plan count).
- **GitHub Copilot in SSMS (Ask Mode)** can explain a stored procedure, spot a
  non-sargable anti-pattern, and propose a sargable rewrite.
- **Agent Mode** can run a **multi-step, read-only investigation** against Query
  Store and return a **DBA review/remediation table**.
- **Human approval and SQL permissions** — not the AI — are the real guardrails.
- A simple, safe fix (sargable rewrite + supporting index) produces a
  **measurable** before/after improvement.
- Partitioning is assessed **with evidence**, not used as a default tuning answer.

## 4. What this demo does not prove

- It is **not** a production reference architecture (a jumpbox + a SQL VM,
  demo-friendly Query Store settings, PAYG SQL license).
- It does **not** show automated/production auto-remediation — every change is
  applied **manually** by the DBA.
- It does **not** benchmark hardware or claim absolute performance numbers; the
  point is the **workflow** and the **relative** before/after delta.
- It is **not** a security-hardened deployment; it is meant for an isolated demo
  subscription with no production data.

## 5. Prerequisites

On your **workstation** (to deploy):
- An Azure subscription that **allows public IPs and VMs** — some heavily governed
  subscriptions block public IPs, so use a dev/test subscription. Rights to create
  a resource group, VNet, and 2 VMs.
- **Azure CLI** 2.50+ (`az version`) and **PowerShell 7+** (`pwsh`).
- An RDP client and your **public IP** (e.g. from <https://ifconfig.me>).

On the **jumpbox** (provisioned by the demo):
- **SSMS 21.x/22.x** with the **GitHub Copilot / AI Assistance** capability
  (see [section 8](#8-installing-or-validating-ssms-with-github-copilot)).
- A **GitHub account with GitHub Copilot**. **Use an *individual* Copilot account**
  (personal GitHub with Copilot Pro or a free trial): the jumpbox is an ordinary
  (unmanaged) VM, so a **corporate** GitHub account federated to Entra will be
  blocked by Conditional Access (*"device is not managed"*). An individual account
  isn't subject to that.

> The SQL Server VM needs **no outbound internet** for Copilot. Only the
> jumpbox/client needs GitHub Copilot connectivity and sign-in.
>
> Note: a managed **Microsoft Dev Box** would let *corporate* Copilot work, but
> Dev Box stopped accepting new tenants on 2025-11-01, so this demo uses a plain
> jumpbox VM + an individual Copilot account.

## 6. Azure deployment steps

1. Copy the example parameters and edit them (no secrets go in this file):
   ```powershell
   cd infra
   Copy-Item parameters.example.json parameters.json
   # Edit parameters.json: set allowedRdpSourceIp to "<your.public.ip>/32"
   ```
   Key parameters (see [infra/parameters.example.json](infra/parameters.example.json)):
   `namePrefix` (default `wwidemo`), `adminUsername` (default `azureadmin`),
   `allowedRdpSourceIp` (**required**), `jumpboxVmSize` (`Standard_D2as_v6`),
   `sqlVmSize` (`Standard_E4as_v6`), `sqlImageSku` (`standard-gen2`),
   `sqlServerLicenseType` (`PAYG`), `sqlAuthLogin` (default `demodba`).

2. Pick a subscription that **allows public IPs**, then deploy. You'll be prompted
   (as SecureStrings) for the **VM admin password** and the **SQL auth password**
   — they are never written to disk:
   ```powershell
   az login
   az account set --subscription "<your-subscription-id>"
   ./deploy.ps1 -ResourceGroup "rg-wwi-copilot-demo" -Location "eastus2"
   ```
   [infra/deploy.ps1](infra/deploy.ps1) registers the required providers, deploys
   the jumpbox + SQL VM + VNet, and prints outputs: `jumpboxFqdn`,
   `jumpboxPublicIp`, `sqlServerPrivateIp`, `sqlServerComputerName`,
   `sqlAuthLoginName`.

3. Note the **`jumpboxFqdn`/`jumpboxPublicIp`** and the **`sqlServerPrivateIp`**
   (and/or `sqlServerComputerName`) — you'll use them next.

## 7. Connecting to the jumpbox

1. RDP to the **`jumpboxFqdn`** (or `jumpboxPublicIp`) from the IP you whitelisted.
2. Sign in with `adminUsername` and the admin password you set during deploy.
3. (First time) Windows may finish post-deploy configuration for a few minutes.

## 8. Installing or validating SSMS with GitHub Copilot

On the jumpbox:
1. Open **SQL Server Management Studio**. If it is not present, install the latest
   **SSMS 21+** from <https://aka.ms/ssms> (SSMS is now based on the Visual Studio
   shell; the **GitHub Copilot** capability ships as a selectable component).
2. In the SSMS/VS Installer, ensure the **GitHub Copilot / AI Assistance**
   component is installed (Modify ▶ Individual components ▶ search "Copilot").
3. Restart SSMS. You should see the **Copilot** Chat pane (Ask) and, where
   available, **Agent Mode**.

> If your SSMS build doesn't yet expose Agent Mode, you can still run the entire
> Ask Mode flow; the Agent Mode steps degrade gracefully to Ask prompts.

## 9. Signing into GitHub Copilot in SSMS

1. Open the **Copilot** pane in SSMS.
2. Click **Sign in** and complete the GitHub flow with an **individual** GitHub
   account that has Copilot (personal GitHub + Copilot Pro or a free trial).
3. Confirm the pane shows you're connected (model picker visible).

> Use an individual account, **not** a corporate GitHub account federated to your
> Entra tenant: the jumpbox is an ordinary (unmanaged) VM, so corporate sign-in is
> blocked by Conditional Access (*"device is not managed"*). The demo only needs a
> valid Copilot entitlement, not a specific identity.

## 10. Connecting from SSMS to the SQL Server VM

1. In SSMS, **Connect ▶ Database Engine**.
2. **Server name:** the SQL VM **private IP** (`sqlServerPrivateIp`) or
   `sqlServerComputerName`. Because the jumpbox and SQL VM share the VNet, private
   connectivity works with no public exposure.
3. **Authentication:**
   - **SQL Server Authentication** with login `demodba` (the `sqlAuthLogin`) and
     the SQL password you set during deploy — simplest for the demo, **or**
   - **Windows Authentication** if you've joined/configured matching accounts
     (preferred in customer environments).
4. Connect to the **`master`** database first; you'll restore WWI next.

## 11. Downloading / restoring WideWorldImporters

You can do this **automated** (PowerShell from the jumpbox) or **manually** (SSMS).

**Automated path** (run on the jumpbox in PowerShell 7):
```powershell
cd <repo>\scripts\powershell

# 1) Download the official backup (idempotent; skips if present)
./01-download-wideworldimporters.ps1 -DestinationPath "C:\SqlBackups\WideWorldImporters-Full.bak"

# 2) If SSMS runs on the jumpbox but the .bak must live on the SQL VM, copy it:
./02-copy-backup-to-sqlvm.ps1 -SqlVmHost "<sqlServerComputerName-or-IP>" -SourcePath "C:\SqlBackups\WideWorldImporters-Full.bak"

# 3) Restore. You'll be prompted for the SQL password; it stays a SecureString and
#    the helper hands it to sqlcmd via an env var internally (never on the command line).
$pw = Read-Host -AsSecureString 'SQL password'
./03-restore-wideworldimporters.ps1 -ServerInstance "<sqlServerPrivateIp>" -SqlLogin "demodba" -SqlPassword $pw -BackupPath "C:\SqlBackups\WideWorldImporters-Full.bak"
```
The restore script reads the backup's logical files and `MOVE`s them to the
instance default data/log paths; it is **idempotent** (skips if the DB exists;
use `-Force` to overwrite with `REPLACE`).

**Manual path (SSMS):** copy `WideWorldImporters-Full.bak` to a path the SQL
service account can read on the **SQL VM** (e.g. `C:\SqlBackups\`), then **Databases ▶
Restore Database ▶ Device**, pick the `.bak`, and restore. The official backup is:
`https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImporters-Full.bak`

Verify by running [scripts/sql/00-verify-wideworldimporters.sql](scripts/sql/00-verify-wideworldimporters.sql)
(checks DB properties and key table row counts; prints PASS/FAIL).

## 12. Enabling Query Store

Run [scripts/sql/01-enable-query-store.sql](scripts/sql/01-enable-query-store.sql)
against **WideWorldImporters**. It enables Query Store in **READ_WRITE** with
**demo-friendly** settings so metrics appear quickly:

| Setting | Demo value | Note |
|---|---|---|
| `OPERATION_MODE` | `READ_WRITE` | capture on |
| `INTERVAL_LENGTH_MINUTES` | `1` | small buckets so windows appear fast |
| `QUERY_CAPTURE_MODE` | `ALL` | capture everything (demo only) |
| `DATA_FLUSH_INTERVAL_SECONDS` | `60` | flush quickly |
| `MAX_STORAGE_SIZE_MB` | `1024` | demo cap |

> **Production note (in-script):** these are deliberately aggressive demo values.
> Real systems should review interval length, `AUTO` capture mode, storage size,
> and cleanup policy with the DBA team. The script ends with a verification query
> against `sys.database_query_store_options`.

## 13. Running setup scripts manually in SSMS

Open and execute these in order against **WideWorldImporters** (each is
idempotent and heavily commented):

| # | Script | What it does |
|---|---|---|
| 02 | [02-create-demo-schema.sql](scripts/sql/02-create-demo-schema.sql) | `Demo` schema, `Demo.LargeInvoiceFact`, `Demo.WorkloadLog` |
| 02b | [02b-amplify-demo-data.sql](scripts/sql/02b-amplify-demo-data.sql) | **Enhanced mode**: amplify `LargeInvoiceFact` to `@TargetRows` (~10M) |
| 03 | [03-create-demo-procedures.sql](scripts/sql/03-create-demo-procedures.sql) | 6 procs: `_Baseline` / `_Regressed` / `_Fixed` × 2 query families |
| 04 | [04-create-baseline-indexes.sql](scripts/sql/04-create-baseline-indexes.sql) | `IX_Demo_*` supporting indexes + `UPDATE STATISTICS` |
| 15 | [15-install-copilot-constitution.sql](scripts/sql/15-install-copilot-constitution.sql) | low-priv `GHCP_DB_User` (least-privilege model), body-only `CONSTITUTION.md` + `AGENTS.md` instructions |

> **Standard vs Enhanced mode.** The demo works on restored WWI as-is (Standard).
> For a **stronger, more obvious** regression on a larger VM, run **02b** to
> amplify `Demo.LargeInvoiceFact` (edit the `@TargetRows` `DECLARE` near the top).
> Enhanced mode is the recommended default for a crisp before/after. The procs in
> 03 target `Demo.LargeInvoiceFact`, so run 02b before the workloads if you want
> the amplified effect.

Run **15** to install the SSMS-native Copilot guardrails — see
[section 21](#21-how-to-show-human-approval-and-guardrails).

## 14. Running the baseline workload

Establish a healthy baseline window in Query Store.

- **In SSMS:** open and run
  [scripts/sql/05-run-baseline-workload.sql](scripts/sql/05-run-baseline-workload.sql)
  (defaults to 25 iterations; logs a `baseline` row to `Demo.WorkloadLog` and
  prints the UTC start/end window).
- **Or PowerShell:**
  ```powershell
  $pw = Read-Host -AsSecureString 'SQL password'
  ./04-run-baseline-workload.ps1 -ServerInstance "<sqlServerPrivateIp>" -SqlLogin "demodba" -SqlPassword $pw
  ```
  (or pass `-UseWindowsAuth` to use integrated authentication instead).

Note the printed **baseline window** — you'll correlate it with Query Store.

## 15. Introducing the performance issue

Run [scripts/sql/06-introduce-performance-issue.sql](scripts/sql/06-introduce-performance-issue.sql).
It **drops the supporting `IX_Demo_LargeInvoiceFact_InvoiceDate` index** (idempotent
`IF EXISTS`) so the regressed, non-sargable query (`YEAR(InvoiceDate) = @Year`)
has no seek to fall back on — making the regression clearly visible. Comments
explain exactly why.

## 16. Running the regressed workload

- **In SSMS:** run
  [scripts/sql/07-run-regressed-workload.sql](scripts/sql/07-run-regressed-workload.sql)
  (15 iterations, `RunLabel='regressed'`, calls the `_Regressed` procedures).
- **Or PowerShell** (also introduces the issue unless `-SkipIntroduceIssue`):
  ```powershell
  ./05-run-regressed-workload.ps1 -ServerInstance "<sqlServerPrivateIp>" -SqlLogin "demodba" -SqlPassword $pw
  ```

## 17. Using the Query Store reports

Run these and read the numbers — this is the **source of truth**:

| Script | Shows |
|---|---|
| [08-query-store-baseline-report.sql](scripts/sql/08-query-store-baseline-report.sql) | per-query/plan metrics over the **baseline** window |
| [09-query-store-regression-report.sql](scripts/sql/09-query-store-regression-report.sql) | **baseline vs regressed** with `duration_x` / `cpu_x` / `reads_x` ratios + multi-plan detection |
| [12-query-store-after-fix-report.sql](scripts/sql/12-query-store-after-fix-report.sql) | **regressed vs fixed** with `speedup_x` |
| [14-show-query-store-plan-details.sql](scripts/sql/14-show-query-store-plan-details.sql) | full plan XML + runtime stats for a `@query_id` you choose |

You can also use SSMS's built-in **Query Store** reports (Database ▶ Query Store ▶
*Top Resource Consuming Queries* / *Regressed Queries*) for the visual story.

## 18. SSMS Ask Mode demo flow

In SSMS, open the **regressed** procedure
(`Demo.usp_GetRegionalSalesByYear_Regressed`) and use the **Copilot Chat (Ask)**
pane with the prompts in [copilot/ask-mode-prompts.md](copilot/ask-mode-prompts.md):

1. *"Explain what this stored procedure does and identify possible performance
   concerns."*
2. *"Rewrite this query to be more sargable without changing the business logic."*
3. *"Based on this execution plan, explain the likely bottleneck in simple DBA
   terms."*
4. *"What evidence would you need before recommending partitioning for this
   table?"*
5. *"Review this index recommendation and tell me what else I should validate
   before creating it."*

Talking point: Copilot spots `YEAR(InvoiceDate) = @Year` as **non-sargable** and
proposes a half-open date range — but **you** confirm with Query Store.

## 19. SSMS Agent Mode demo flow

Switch to **Agent Mode** and use [copilot/agent-mode-prompts.md](copilot/agent-mode-prompts.md).
Agent Mode runs a **multi-step, read-only** investigation against Query Store:

1. Investigate the regression (Query Store, **no changes**, return a DBA review
   table).
2. Compare baseline vs regressed windows; list top queries by duration/CPU/reads
   with `query_id`, `plan_id`, likely cause, next action.
3. Analyze the worst query; weigh rewrite/index/stats/plan-forcing/hints/
   partitioning — **don't implement**.
4. Produce a remediation plan (risk, expected benefit, validation, rollback).
5. Generate the **T-SQL to review** for the safest fix — **do not execute**.
6. Assess whether partitioning is justified, with evidence.

The three Agent Skills shape this behavior:
[query-store-regression-review](.github/skills/query-store-regression-review/SKILL.md),
[index-recommendation-validation](.github/skills/index-recommendation-validation/SKILL.md),
[partitioning-assessment](.github/skills/partitioning-assessment/SKILL.md).

## 20. Prompts to copy/paste into SSMS Copilot

A single copy/paste cheat sheet tying prompts to each step lives in
[copilot/ssms-demo-prompts.md](copilot/ssms-demo-prompts.md). The presenter script
(what to *say*) is in [copilot/expected-demo-narrative.md](copilot/expected-demo-narrative.md).

## 21. How to show human approval and guardrails

This demo makes the guardrails **real**, not just verbal:

- **SSMS-native database instructions.** Running
  [15-install-copilot-constitution.sql](scripts/sql/15-install-copilot-constitution.sql)
  installs a database-level **`CONSTITUTION.md`** extended property and object-level
  **`AGENTS.md`** properties. SSMS Copilot reads these automatically when connected
  to WideWorldImporters. (Explanation:
  [copilot/ssms-database-constitution.md](copilot/ssms-database-constitution.md),
  [copilot/ssms-database-instructions.md](copilot/ssms-database-instructions.md).)
- **Least privilege is the real boundary.** By default, Copilot in SSMS runs SQL
  **under the login you connect with** — it has *no* separate permissions and *no*
  elevated access. So the security control is **which login you connect SSMS
  with**: use a least-privilege one. Script 15 creates **`GHCP_DB_User`**, a
  read-only principal with only `SELECT` + `EXECUTE ON Demo` + `VIEW DATABASE
  STATE` (no `INSERT/UPDATE/DELETE/ALTER/DROP/CREATE`), to *model* exactly such an
  investigator. Show the boundary live:
  ```sql
  EXECUTE AS USER = 'GHCP_DB_User';
  SELECT TOP (1) * FROM Demo.LargeInvoiceFact;      -- allowed (read)
  UPDATE Demo.LargeInvoiceFact SET Quantity = 0;    -- blocked: no permission
  REVERT;
  ```
  Even if a prompt asks for a change, a least-privilege login simply **cannot**
  perform DML/DDL — SQL Server blocks it.
- **Approvals in Agent Mode.** Approve only **read-only** investigation steps
  first. Show that *approvals are a workflow control* — **SQL permissions are the
  security control**.

> **Optional corner case — pin Copilot to a specific user.** The constitution is
> installed **body-only** by default (Copilot runs as whoever is connected). If you
> want Copilot to *always* run as one fixed identity regardless of who connects,
> add an `agentExecuteAsUser: <login>` line to the constitution's YAML front
> matter; SSMS then runs every Copilot query via `EXECUTE AS` for that identity.
> Use a **SQL login**, not a `WITHOUT LOGIN` database user — a database user gives
> a database-scoped token with no server context and makes Copilot fail to
> initialize (*"GitHub Copilot in SSMS does not have support for this connection
> context"*), whereas a login keeps server scope. The connected login also needs
> `IMPERSONATE` on that identity. A commented template is at the end of
> [15-install-copilot-constitution.sql](scripts/sql/15-install-copilot-constitution.sql).
> For most demos, connecting with a least-privilege login is simpler and is the
> recommended model.

> Copilot/Agent Mode should **not** be treated as a security boundary. SQL Server
> permissions are the real control. See [Appendix B](#appendix-b--security-and-guardrails).

## 22. Applying a safe fix

Open [scripts/sql/10-apply-fix-options.sql](scripts/sql/10-apply-fix-options.sql).
It is organized into clearly-commented options — **it does not blindly apply
everything**. Each section documents *when to use it, the risk, how to validate,
how to roll back*:

- **Option A** — rewrite to a **sargable** predicate / use the `_Fixed` procedures
  (the recommended default fix; informational).
- **Option B** — recreate the supporting `IX_Demo_LargeInvoiceFact_InvoiceDate`
  index (**runs**).
- **Option C** — `UPDATE STATISTICS ... WITH FULLSCAN` (**runs**).
- **Option D** — `sp_query_store_force_plan` example (**template/commented**).
- **Option E** — `sys.sp_query_store_set_hints` example (**template/commented**).
- **Rollback** — commands to undo each (**commented**).

Recommended demo fix: **sargable rewrite (use `_Fixed`) + recreate the demo
index**, applied **manually**. No production-style auto-remediation.

## 23. Showing before/after improvement

1. Run the fixed workload:
   - **SSMS:** [scripts/sql/11-run-fixed-workload.sql](scripts/sql/11-run-fixed-workload.sql)
     (25 iterations, `RunLabel='fixed'`, calls `_Fixed` procs), or
   - **PowerShell:** `./06-run-fixed-workload.ps1 -ServerInstance "<ip>" -SqlLogin "demodba" -SqlPassword $pw -ApplyFixFirst`
     (the `-ApplyFixFirst` switch recreates the index before running).
2. Run [12-query-store-after-fix-report.sql](scripts/sql/12-query-store-after-fix-report.sql)
   to show the **`speedup_x`** of fixed vs regressed (lower duration, far fewer
   logical reads, seek instead of scan).
3. Optionally open SSMS Query Store's **Regressed Queries** view to show the dots
   move back.

## 24. Partitioning assessment discussion

Run [scripts/sql/13-partitioning-assessment-helper.sql](scripts/sql/13-partitioning-assessment-helper.sql).
It reports table size, partition status, row distribution by year and year-month,
and existing indexes, then prints a decision checklist. Use it with the
[partitioning-assessment skill](.github/skills/partitioning-assessment/SKILL.md) to
discuss partitioning **responsibly**:

> **Partitioning is not a generic query tuning fix.** Validate workload,
> maintenance, retention, data volume, and index alignment before recommending it.
> In this demo, the right fix is the **sargable rewrite + index**, not
> partitioning.

## 25. Resetting the demo

To run the demo again from a clean state **without** re-restoring WWI:

- **SSMS:** run [scripts/sql/99-reset-demo.sql](scripts/sql/99-reset-demo.sql).
- **PowerShell:** `./99-reset-demo.ps1 -ServerInstance "<ip>" -SqlLogin "demodba" -SqlPassword $pw`.

This drops the `CONSTITUTION.md`/`AGENTS.md` extended properties, `GHCP_DB_User`,
and all `Demo` procedures/indexes/tables/schema — and leaves the native
WideWorldImporters objects **intact**. Re-run scripts 02 → 04 (+ 02b for Enhanced
mode) and 15 to rebuild.

## 26. Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| **Bicep deployment failure** | Re-run `./deploy.ps1`; check `az deployment group create` error detail. Confirm region capacity and that your subscription allows the VM sizes. |
| **Deployment fails at preflight but `validate` passes** (`MissingSubscriptionRegistration`) | A required resource provider isn't registered on the subscription — most often `Microsoft.SqlVirtualMachine`. `validate` doesn't check this; `create` does. `deploy.ps1` now auto-registers and waits, but you can do it manually: `az provider register --namespace Microsoft.SqlVirtualMachine --wait`. |
| **Deployment fails with `InvalidTemplate` / `adminPassword ... Length ... >= '12'`** | The password you entered is shorter than 12 characters (the prompt doesn't force it). `deploy.ps1` now checks length up front and passes secrets via a temp file, so re-run and enter a **12+ char complex** password (upper + lower + digit + special, not containing the username). |
| **VM SKU unavailable** (`SkuNotAvailable` / `NotAvailableForSubscription`) | Your subscription's offer doesn't allow the chosen size in that region. List sizes that **are** available and pick one: `az vm list-skus -l <region> --resource-type virtualMachines --query "[?!(restrictions)].name" -o tsv`. Set `jumpboxVmSize` / `sqlVmSize` in `parameters.json` accordingly. Defaults here are `Standard_D2as_v6` / `Standard_E4as_v6`. Note: Azure CLI 2.77.0 may print `The content for this response was already consumed` instead of the real `SkuNotAvailable` error — `deploy.ps1` prints diagnostic guidance when this happens. |
| **RDP blocked** | Your public IP changed or `allowedRdpSourceIp` is wrong. Update the parameter (`/32`) and redeploy, or fix the jumpbox NSG rule. |
| **Copilot sign-in blocked ("device is not managed")** | You signed in with a **corporate** GitHub account federated to Entra; the jumpbox is an unmanaged VM, so Conditional Access blocks it. Sign in with an **individual** Copilot account (personal GitHub + Copilot Pro / trial) instead. |
| **Public IP creation blocked** (`SubscriptionNotRegisteredForFeature` / `AllowBringYourOwnPublicIpAddress`) | The deploy subscription's governance blocks public IPs. Deploy into a dev/test subscription that allows them (quick check: `az network public-ip create` in a throwaway RG). |
| **SSMS cannot connect to SQL Server** | Use the **private IP** (`10.20.2.10`); confirm you're on the jumpbox; check the SQL VM NSG allows 1433 from the jumpbox subnet; confirm SQL is up and TCP/IP enabled; confirm SQL auth login/password. |
| **WideWorldImporters backup download failed** | Network/proxy issue. Re-run `01-download-...` with `-Force`, or download the `.bak` manually from the official URL and place it at the expected path. |
| **Restore failed (bad backup path)** | The `.bak` must be readable by the **SQL service account on the SQL VM** (e.g. `C:\SqlBackups\`). Copy it there (script 02) and re-run restore. |
| **Query Store empty** | Workload didn't run long enough / Query Store not enabled. Re-run `01-enable-query-store.sql`, then the workload; wait past one `INTERVAL_LENGTH_MINUTES` (1 min) and re-flush. |
| **Regression not visible enough** | Use **Enhanced mode**: run `02b-amplify-demo-data.sql` to grow `Demo.LargeInvoiceFact`, ensure the index was dropped (script 06), and increase workload iterations. |
| **Copilot not available in SSMS** | Install the **GitHub Copilot / AI Assistance** component (section 8) and sign in (section 9); update SSMS to the latest build. |
| **Agent Mode not available** | Your SSMS build may not expose it yet; use the Ask Mode prompts instead, or update SSMS. |
| **Permission denied for execution plan / Query Store views** | The principal needs `VIEW DATABASE STATE`. `GHCP_DB_User` is granted it by script 15; for your own login, grant it in a non-prod DB. |
| **Workload scripts run too slowly** | Lower `@Iterations` in the workload `.sql`, or reduce `@TargetRows` in `02b`; right-size the SQL VM. |
| **Fix shows no measurable improvement** | Confirm you ran the `_Fixed` procs **and** recreated `IX_Demo_LargeInvoiceFact_InvoiceDate`, and that `UPDATE STATISTICS` ran; compare the correct Query Store windows (12). |

## 27. Cleanup

Delete **everything** by removing the resource group:
```powershell
cd infra
./destroy.ps1 -ResourceGroup "rg-wwi-copilot-demo"
```
[infra/destroy.ps1](infra/destroy.ps1) confirms the RG name and runs
`az group delete --yes --no-wait`. To only reset the demo objects (keep the VMs),
use [section 25](#25-resetting-the-demo) instead.

## 28. On-prem parallels and customer notes

How this maps to a real customer estate:

- The **Azure SQL Server VM** represents the customer's **on-prem SQL Server
  2019/2022** instance.
- The **jumpbox** represents the customer's existing **DBA/admin jump server**.
- **SSMS with Copilot runs on the jumpbox**, *not* on the database server.
- The **database server needs no outbound internet** for Copilot in this model.
- The **jumpbox/client** needs **GitHub Copilot connectivity and sign-in** (an
  individual Copilot account avoids corporate managed-device policies; on-prem a
  managed admin workstation would let a corporate account sign in).
- The **same Query Store scripts and DBA workflow** apply to SQL Server 2019/2022,
  with version-specific validation.
- Use **non-production first**.
- Use **least privilege**.
- Use a **dedicated low-privilege login** for AI-assisted investigation if
  possible (this demo's `GHCP_DB_User`).
- **Do not allow automated write/schema changes in production.**
- Keep **Agent Mode read-only** for initial pilots.
- Use **DBA-owned skills/runbooks** to standardize how Copilot evaluates indexes,
  regressions, and partitioning (the `.github/skills/` files here).
- Any **customer data sent through prompts or context** must follow the customer's
  **security/compliance policies**.

> **Alternative targets.** You *could* run a similar workflow against **Azure SQL
> Database** or **Azure SQL Managed Instance**, but this demo intentionally uses a
> **SQL Server VM** because it maps most directly to on-prem SQL Server. See the
> notes in [infra/parameters.example.json](infra/parameters.example.json).

---

## Appendix A — Manual SSMS demo flow (24 steps)

The explicit click-path to present live:

1. RDP into the jumpbox.
2. Open SSMS.
3. Connect to the SQL Server VM using its private IP or DNS name.
4. Restore WideWorldImporters if not already restored.
5. Open `scripts/sql/00-verify-wideworldimporters.sql`.
6. Execute the setup scripts in order (02, 02b optional, 03, 04, 15).
7. Confirm Query Store is enabled (`01-enable-query-store.sql`).
8. Run the baseline workload (`05-run-baseline-workload.sql`).
9. Run the baseline Query Store report (`08-...`).
10. Introduce the regression (`06-introduce-performance-issue.sql`).
11. Run the regressed workload (`07-run-regressed-workload.sql`).
12. Run the regression Query Store report (`09-...`).
13. Open the regressed stored procedure in SSMS.
14. Ask Copilot in **Ask Mode** to explain the query.
15. Ask Copilot to identify anti-patterns.
16. Switch to **Agent Mode**.
17. Ask Agent Mode to investigate the regression using Query Store.
18. Approve only **read-only** investigation steps at first.
19. Ask Agent Mode to produce a **DBA remediation table**.
20. Manually apply the selected fix (`10-apply-fix-options.sql`).
21. Run the fixed workload (`11-run-fixed-workload.sql`).
22. Run the after-fix Query Store report (`12-...`).
23. Show measurable improvement.
24. Reset the demo if needed (`99-reset-demo.sql`).

## Appendix B — Security and guardrails

- This demo should run in an **isolated demo environment**.
- **Do not use production customer data.**
- **Do not expose SQL Server publicly** (the SQL VM has no public endpoint).
- **Restrict the RDP source IP** (`allowedRdpSourceIp`, `/32`).
- **Prefer Windows authentication** where feasible.
- **Review every Copilot-generated script** before running it.
- **Copilot/Agent Mode is not a security boundary** — SQL Server permissions are
  the real control (`GHCP_DB_User`).
- **Any schema changes should be reviewed and applied manually in test first.**

## Appendix C — Repository layout

```text
sql-ai-dba-copilot-demo/
  README.md
  infra/                 main.bicep, parameters.example.json, deploy.ps1, destroy.ps1
  scripts/
    powershell/          00..06 drivers + 99-reset + _Common.ps1
    sql/                 00..15 demo scripts + 99-reset
  copilot/               ask/agent/demo prompts, narrative, SSMS DB instructions
  .github/skills/        query-store-regression-review, index-recommendation-validation,
                         partitioning-assessment
```

## Appendix D — Acceptance criteria

This repo lets you: deploy infra with Bicep → connect to the jumpbox → connect
SSMS to the SQL VM → restore WWI → enable Query Store → create demo procs/indexes →
run a baseline → introduce a clear regression → run the regressed workload →
compare before/after in Query Store → use **Ask Mode** to explain/refactor a query
→ use **Agent Mode** to investigate → apply a safe fix manually → rerun the
workload → show measurable improvement → reset the demo.
