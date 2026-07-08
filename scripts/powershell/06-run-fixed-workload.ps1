<#
.SYNOPSIS
    Runs the fixed workload after the remediation has been applied.

.DESCRIPTION
    Thin PowerShell driver that executes scripts/sql/11-run-fixed-workload.sql.
    Run this AFTER applying the fix (scripts/sql/10-apply-fix-options.sql) so the
    date index exists again and the sargable _Fixed procedures are exercised.

    Use -ApplyFixFirst to run 10-apply-fix-options.sql (Sections B + C are
    idempotent) before the workload.

.EXAMPLE
    $pwd = Read-Host -AsSecureString 'SQL password'
    ./06-run-fixed-workload.ps1 -ServerInstance 10.20.2.10 -SqlLogin demodba -SqlPassword $pwd -ApplyFixFirst
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ServerInstance,
    [string]$Database = 'WideWorldImporters',
    [string]$SqlLogin,
    [System.Security.SecureString]$SqlPassword,
    [switch]$UseWindowsAuth,
    [switch]$ApplyFixFirst
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/_Common.ps1"

$sqlDir  = Resolve-Path (Join-Path $PSScriptRoot '..' 'sql')
$fixSql  = Join-Path $sqlDir '10-apply-fix-options.sql'
$workSql = Join-Path $sqlDir '11-run-fixed-workload.sql'

$ctx = New-DemoSqlContext -ServerInstance $ServerInstance -Database $Database `
    -SqlLogin $SqlLogin -SqlPassword $SqlPassword -UseWindowsAuth:$UseWindowsAuth

if ($ApplyFixFirst) {
    Write-Host '[INFO] Applying the fix (10-apply-fix-options.sql)...' -ForegroundColor Cyan
    Invoke-DemoSqlFile -Context $ctx -InputFile $fixSql
}

Write-Host '[INFO] Running FIXED workload...' -ForegroundColor Cyan
Invoke-DemoSqlFile -Context $ctx -InputFile $workSql
Write-Host '[OK]  Fixed workload complete.' -ForegroundColor Green
