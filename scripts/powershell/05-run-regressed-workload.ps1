<#
.SYNOPSIS
    Introduces the regression and runs the slow (regressed) workload.

.DESCRIPTION
    By default this first runs scripts/sql/06-introduce-performance-issue.sql
    (drops the supporting date index) and then scripts/sql/07-run-regressed-workload.sql
    (drives the non-sargable procedures). Use -SkipIntroduceIssue to only run the
    workload (e.g. if you already dropped the index manually).

    The SQL scripts own the loop and write the run window to Demo.WorkloadLog.

.EXAMPLE
    $pwd = Read-Host -AsSecureString 'SQL password'
    ./05-run-regressed-workload.ps1 -ServerInstance 10.20.2.10 -SqlLogin demodba -SqlPassword $pwd
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ServerInstance,
    [string]$Database = 'WideWorldImporters',
    [string]$SqlLogin,
    [System.Security.SecureString]$SqlPassword,
    [switch]$UseWindowsAuth,
    [switch]$SkipIntroduceIssue
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/_Common.ps1"

$sqlDir   = Resolve-Path (Join-Path $PSScriptRoot '..' 'sql')
$introSql = Join-Path $sqlDir '06-introduce-performance-issue.sql'
$workSql  = Join-Path $sqlDir '07-run-regressed-workload.sql'

$ctx = New-DemoSqlContext -ServerInstance $ServerInstance -Database $Database `
    -SqlLogin $SqlLogin -SqlPassword $SqlPassword -UseWindowsAuth:$UseWindowsAuth

if (-not $SkipIntroduceIssue) {
    Write-Host '[INFO] Introducing the performance issue (dropping the date index)...' -ForegroundColor Cyan
    Invoke-DemoSqlFile -Context $ctx -InputFile $introSql
}

Write-Host '[INFO] Running REGRESSED workload (this is intentionally slow)...' -ForegroundColor Cyan
Invoke-DemoSqlFile -Context $ctx -InputFile $workSql
Write-Host '[OK]  Regressed workload complete.' -ForegroundColor Green
