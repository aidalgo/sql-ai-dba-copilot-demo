# Optional Azure demo environment

This guide creates a disposable Azure environment for the SQL Server and GitHub
Copilot in SSMS exercise. It is optional. If you already have a nonproduction
SQL Server where you can restore WideWorldImporters, enable Query Store, and
create the `Demo` schema, return to the [main learning guide](../README.md).

The environment exists only to make the SSMS exercise reproducible. It is not a
production reference architecture or a requirement for GitHub Copilot in SSMS.

## What the deployment creates

```text
Azure resource group
+------------------------------------------------------------------+
| Virtual network                                                  |
|                                                                  |
|  jumpbox subnet                    SQL subnet                     |
|  +--------------------------+      +---------------------------+  |
|  | Windows Server jumpbox   |1433  | SQL Server 2022 VM        |  |
|  | - public RDP from one IP |----->| - private IP only         |  |
|  | - SSMS + GitHub Copilot  |      | - SQL authentication      |  |
|  +--------------------------+      +---------------------------+  |
+------------------------------------------------------------------+
```

- The jumpbox represents a DBA workstation or administrative jump server.
- The SQL VM has no public IP. SQL traffic is allowed from the jumpbox subnet.
- RDP to the jumpbox is restricted to the source IP or CIDR supplied at deploy
  time.
- RDP and WinRM to the SQL VM are allowed only from the jumpbox subnet. They are
  optional management paths, not requirements of the Copilot workflow.

The resources are defined in [main.bicep](main.bicep).

## Prerequisites

On the workstation used to deploy Azure resources:

- An Azure subscription that permits public IP addresses and virtual machines.
- Rights to create a resource group, virtual network, public IP, and two VMs.
- Azure CLI 2.50 or later.
- PowerShell 7 or later.
- An RDP client.
- Your current public IP address, normally expressed as a `/32` CIDR.

The SQL Server image uses paid licensing by default. Delete the resource group
when the exercise is complete.

## Deploy the environment

1. Copy the parameter example and set the allowed RDP source:

   ```powershell
   cd infra
   Copy-Item parameters.example.json parameters.json
   # Set allowedRdpSourceIp in parameters.json to "<your.public.ip>/32".
   ```

2. Select the subscription and deploy:

   ```powershell
   az login
   az account set --subscription "<your-subscription-id>"
   ./deploy.ps1 -ResourceGroup "rg-wwi-copilot-demo" -Location "eastus2"
   ```

   The script prompts for the VM administrator password and SQL authentication
   password as secure strings. It registers required resource providers, deploys
   the resources, and prints these outputs:

   - `jumpboxFqdn`
   - `jumpboxPublicIp`
   - `sqlServerPrivateIp`
   - `sqlServerComputerName`
   - `sqlAuthLoginName`

3. Save the output values for the connection and restore steps.

## Connect to the jumpbox

1. RDP to `jumpboxFqdn` or `jumpboxPublicIp`.
2. Sign in with the `adminUsername` from `parameters.json` and the password used
   during deployment.
3. Allow Windows to finish first-login configuration.

## Put the repository on the jumpbox

The SQL scripts and workspace skills must be available on the machine running
SSMS. Clone the repository on the jumpbox:

```powershell
git clone https://github.com/aidalgo/sql-ai-dba-copilot-demo.git
cd sql-ai-dba-copilot-demo
```

If Git is unavailable, download the repository ZIP from GitHub and extract it to
a stable folder. The repository root must contain `.github\skills` for SSMS to
discover the bundled workspace skills.

## Install SSMS and GitHub Copilot

Follow the [SSMS first-use steps in the main guide](../README.md#get-github-copilot-working-in-ssms).
Install SSMS 22.7 or later with the **AI Assistance** workload, sign in to GitHub
Copilot, and then return here to prepare the database.

A GitHub account with Copilot access, including Copilot Free, can be used. A
corporate account can also be used when organizational policy permits sign-in
from the jumpbox. If Conditional Access requires a managed device, use an
approved managed workstation or a separate account permitted for this isolated
lab.

## Connect from SSMS to the SQL VM

1. In SSMS, select **Connect > Database Engine**.
2. Use `sqlServerPrivateIp` or `sqlServerComputerName` as the server name.
3. Use the `sqlAuthLoginName` output and the SQL password supplied during
   deployment. Windows authentication requires an identity configuration shared
   by both machines and is not configured by this template.
4. Connect to `master` initially.

From PowerShell on the jumpbox, you can validate the basic client and connection:

```powershell
cd <repo>\scripts\powershell
$pw = Read-Host -AsSecureString 'SQL password'
./00-validate-prereqs.ps1 `
  -ServerInstance "<sqlServerPrivateIp>" `
  -SqlLogin "demodba" `
  -SqlPassword $pw
```

## Restore WideWorldImporters

The backup must end up on storage visible to the SQL Server service. Choose the
transfer method that fits the environment.

### Option A: Use your normal transfer process

If your organization already has an approved backup-transfer and restore
process, use it. No WinRM configuration is required. Place the backup somewhere
the SQL Server service can read and restore it through SSMS or the supplied
restore script.

### Option B: Download directly on the SQL VM

For the Azure environment, this is the simplest method and avoids workgroup
remoting configuration:

1. From the jumpbox, RDP to the SQL VM private address. The NSG permits this only
   from the jumpbox subnet.
2. Copy or clone the repository onto the SQL VM.
3. Run:

   ```powershell
   cd <repo>\scripts\powershell
   ./01-download-wideworldimporters.ps1 `
     -DestinationPath "C:\SqlBackups\WideWorldImporters-Full.bak"
   ```

4. Return to the jumpbox for the restore and SSMS exercise.

### Option C: Copy with PowerShell remoting

Use this option only when running from the provisioned jumpbox to the provisioned
SQL VM, or when your own environment already supports PowerShell remoting.
Opening TCP 5985 in the NSG is not sufficient by itself. The template creates
standalone workgroup VMs, so Kerberos is unavailable and the client must trust
the remote host or use WinRM over HTTPS.

For an isolated demo, configure the specific SQL VM address as a trusted host.
Run these commands from an elevated Windows PowerShell session on the jumpbox:

```powershell
$sqlVm = '<sqlServerPrivateIp>'
Set-Item WSMan:\localhost\Client\TrustedHosts `
  -Value $sqlVm `
  -Concatenate `
  -Force
Test-WSMan -ComputerName $sqlVm
```

If `Test-WSMan` fails, sign in to the SQL VM and run `Enable-PSRemoting -Force`,
then test again. Use only the specific private address, not `*`, in
`TrustedHosts`.

Download on the jumpbox and copy with the local VM administrator credential:

```powershell
cd <repo>\scripts\powershell
./01-download-wideworldimporters.ps1 `
  -DestinationPath "C:\SqlBackups\WideWorldImporters-Full.bak"

./02-copy-backup-to-sqlvm.ps1 `
  -SqlVmHost "<sqlServerPrivateIp>" `
  -SourcePath "C:\SqlBackups\WideWorldImporters-Full.bak"
```

If local-account remote UAC policy blocks the copy, prefer Option B rather than
weakening that policy solely for the demo.

### Restore the backup

After the backup is on the SQL VM, restore it from the jumpbox:

```powershell
cd <repo>\scripts\powershell
$pw = Read-Host -AsSecureString 'SQL password'
./03-restore-wideworldimporters.ps1 `
  -ServerInstance "<sqlServerPrivateIp>" `
  -SqlLogin "demodba" `
  -SqlPassword $pw `
  -BackupPath "C:\SqlBackups\WideWorldImporters-Full.bak"
```

The supplied script targets the logical file names in the pinned Microsoft
WideWorldImporters backup and relocates them to the instance default data and log
paths. It skips an existing database unless `-Force` is supplied.

Return to the [main learning guide](../README.md#prepare-the-wideworldimporters-exercise)
to verify the restore, enable Query Store, populate the demo data, and begin the
Copilot exercise.

## Azure environment troubleshooting

| Symptom | Likely cause and action |
| --- | --- |
| Bicep deployment fails | Rerun `deploy.ps1` and inspect the deployment error. Confirm subscription policy and regional VM availability. |
| `MissingSubscriptionRegistration` | Register the named provider. The deploy script registers and waits for Compute, Network, and SQL VM providers. |
| Password validation fails | Use a password of at least 12 characters that meets Azure VM complexity requirements and does not contain the username. |
| `SkuNotAvailable` | Choose unrestricted VM sizes from `az vm list-skus` and update `parameters.json`. |
| RDP is blocked | Confirm your current public IP matches `allowedRdpSourceIp` and redeploy or update the NSG rule. |
| Public IP creation is denied | Use a dev/test subscription that permits public IPs, or use an existing environment instead of this template. |
| SSMS cannot connect to SQL | Use the SQL VM private address from the jumpbox and verify TCP 1433, SQL service state, and credentials. |
| Backup copy reports a WinRM trust error | Use direct download on the SQL VM, or configure the specific SQL VM in `TrustedHosts` as described above. |
| Backup path is rejected | Confirm the path is local to the SQL VM and readable by the SQL Server service account. |
| Copilot sign-in says the device is unmanaged | Organizational Conditional Access is blocking the unmanaged jumpbox. Use an approved managed client or an account allowed for the isolated lab. |

For Copilot, Agent mode, skills, Query Store, and workload issues, use the
[main troubleshooting table](../README.md#troubleshooting).

## Cleanup

Remove the entire environment when finished:

```powershell
cd infra
./destroy.ps1 -ResourceGroup "rg-wwi-copilot-demo"
```

The script confirms the resource-group name and starts an asynchronous resource
group deletion. To preserve the VMs and only remove demo database objects, run
[scripts/sql/99-reset-demo.sql](../scripts/sql/99-reset-demo.sql) instead.
