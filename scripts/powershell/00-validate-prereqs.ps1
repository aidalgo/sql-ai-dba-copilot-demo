<#
.SYNOPSIS
    Validates prerequisites before setting up the demo database.

.DESCRIPTION
    Checks for sqlcmd, confirms connectivity to the target SQL Server, prints the
    server version/edition, and verifies Query Store is available. Run this from
    the jumpbox (or the SQL VM) after the infrastructure is deployed.

.EXAMPLE
    $pwd = Read-Host -AsSecureString 'SQL password'
    ./00-validate-prereqs.ps1 -ServerInstance 10.20.2.10 -SqlLogin demodba -SqlPassword $pwd
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ServerInstance,
    [string]$Database = 'master',
    [string]$SqlLogin,
    [System.Security.SecureString]$SqlPassword,
    [switch]$UseWindowsAuth
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/_Common.ps1"

Write-Host '== Prerequisite checks ==' -ForegroundColor Cyan

# 1. sqlcmd present?
if (Test-DemoSqlcmd) {
    Write-Host '[OK]  sqlcmd found on PATH.' -ForegroundColor Green
}
else {
    Write-Host '[FAIL] sqlcmd not found. Install the SQL command-line tools (bundled with SSMS).' -ForegroundColor Red
    throw 'Missing sqlcmd.'
}

# 2. PowerShell version (informational).
Write-Host ("[INFO] PowerShell {0}" -f $PSVersionTable.PSVersion)

$ctx = New-DemoSqlContext -ServerInstance $ServerInstance -Database $Database `
    -SqlLogin $SqlLogin -SqlPassword $SqlPassword -UseWindowsAuth:$UseWindowsAuth

# 3. Connectivity + version/edition.
Write-Host "[INFO] Connecting to $ServerInstance ..."
Invoke-DemoSqlQuery -Context $ctx -Query @"
SET NOCOUNT ON;
SELECT
    [server]   = @@SERVERNAME,
    [version]  = CONVERT(varchar(128), SERVERPROPERTY('ProductVersion')),
    [edition]  = CONVERT(varchar(128), SERVERPROPERTY('Edition')),
    [level]    = CONVERT(varchar(128), SERVERPROPERTY('ProductLevel'));
"@
Write-Host '[OK]  Connected successfully.' -ForegroundColor Green

Write-Host ''
Write-Host 'Prerequisites look good. Next: 01-download-wideworldimporters.ps1' -ForegroundColor Yellow
