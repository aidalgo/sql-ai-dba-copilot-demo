<#
.SYNOPSIS
    Runs the baseline (healthy) workload and records it in Query Store.

.DESCRIPTION
    Thin PowerShell driver that executes scripts/sql/05-run-baseline-workload.sql
    against the target server. The SQL script owns the loop and writes the run
    window to Demo.WorkloadLog (single source of truth, no duplicated loop logic).

.EXAMPLE
    $pwd = Read-Host -AsSecureString 'SQL password'
    ./04-run-baseline-workload.ps1 -ServerInstance 10.20.2.10 -SqlLogin demodba -SqlPassword $pwd
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ServerInstance,
    [string]$Database = 'WideWorldImporters',
    [string]$SqlLogin,
    [System.Security.SecureString]$SqlPassword,
    [switch]$UseWindowsAuth
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/_Common.ps1"

$sql = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..' 'sql')) '05-run-baseline-workload.sql'
$ctx = New-DemoSqlContext -ServerInstance $ServerInstance -Database $Database `
    -SqlLogin $SqlLogin -SqlPassword $SqlPassword -UseWindowsAuth:$UseWindowsAuth

Write-Host '[INFO] Running BASELINE workload...' -ForegroundColor Cyan
Invoke-DemoSqlFile -Context $ctx -InputFile $sql
Write-Host '[OK]  Baseline workload complete.' -ForegroundColor Green
