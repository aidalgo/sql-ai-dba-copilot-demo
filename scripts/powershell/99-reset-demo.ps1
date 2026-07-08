<#
.SYNOPSIS
    Resets the demo: drops all Demo-schema objects and Copilot instructions,
    leaving WideWorldImporters intact.

.DESCRIPTION
    Thin PowerShell driver that executes scripts/sql/99-reset-demo.sql against the
    target server. The SQL script owns all drop logic (single source of truth) and
    is idempotent.

.EXAMPLE
    $pw = Read-Host -AsSecureString 'SQL password'
    ./99-reset-demo.ps1 -ServerInstance 10.20.2.10 -SqlLogin demodba -SqlPassword $pw
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

$sql = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..' 'sql')) '99-reset-demo.sql'
$ctx = New-DemoSqlContext -ServerInstance $ServerInstance -Database $Database `
    -SqlLogin $SqlLogin -SqlPassword $SqlPassword -UseWindowsAuth:$UseWindowsAuth

Write-Host '[INFO] Resetting demo objects (WideWorldImporters is preserved)...' -ForegroundColor Cyan
Invoke-DemoSqlFile -Context $ctx -InputFile $sql
Write-Host '[OK]  Demo reset complete. Re-run 02-04 (+ 02b) and 15 to rebuild.' -ForegroundColor Green
