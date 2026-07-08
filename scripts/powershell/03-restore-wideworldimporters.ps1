<#
.SYNOPSIS
    Restores the WideWorldImporters sample database from the .bak.

.DESCRIPTION
    Runs RESTORE DATABASE on the target SQL Server, relocating all data/log files
    (including the In-Memory OLTP filegroup) to the instance default data/log
    directories. Idempotent: if the database already exists it is skipped unless
    -Force is supplied (which restores WITH REPLACE).

    The backup path must be a path on the SQL Server machine that the SQL Server
    service account can read (e.g. C:\SqlBackups\WideWorldImporters-Full.bak), not
    a path on the jumpbox.

.PARAMETER BackupPath
    Path to WideWorldImporters-Full.bak as seen by the SQL Server service.

.EXAMPLE
    $pwd = Read-Host -AsSecureString 'SQL password'
    ./03-restore-wideworldimporters.ps1 -ServerInstance 10.20.2.10 -SqlLogin demodba `
        -SqlPassword $pwd -BackupPath 'C:\SqlBackups\WideWorldImporters-Full.bak'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ServerInstance,
    [string]$Database = 'WideWorldImporters',
    [Parameter(Mandatory)][string]$BackupPath,
    [string]$SqlLogin,
    [System.Security.SecureString]$SqlPassword,
    [switch]$UseWindowsAuth,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/_Common.ps1"

# Connect to master to run the restore.
$ctx = New-DemoSqlContext -ServerInstance $ServerInstance -Database 'master' `
    -SqlLogin $SqlLogin -SqlPassword $SqlPassword -UseWindowsAuth:$UseWindowsAuth

# Idempotency check.
$existsOut = Invoke-DemoSqlQuery -Context $ctx -Variables @{ DbName = $Database } -Query @"
SET NOCOUNT ON;
IF DB_ID(N'`$(DbName)') IS NULL SELECT 'MISSING' ELSE SELECT 'EXISTS';
"@
$alreadyExists = ($existsOut -join "`n") -match 'EXISTS'

if ($alreadyExists -and -not $Force) {
    Write-Host "[SKIP] Database '$Database' already exists. Use -Force to restore WITH REPLACE." -ForegroundColor Yellow
    return
}

$replace = ($alreadyExists -and $Force) ? 1 : 0
Write-Host "[INFO] Restoring '$Database' from $BackupPath (REPLACE=$replace) ..." -ForegroundColor Cyan

# Dynamic RESTORE that relocates every logical file to the instance defaults.
# Logical file names below are stable for the released WideWorldImporters-Full.bak.
$restoreSql = @"
SET NOCOUNT ON;
DECLARE @bak     nvarchar(4000) = N'`$(BackupPath)';
DECLARE @db      sysname        = N'`$(DbName)';
DECLARE @replace bit            = `$(Replace);
DECLARE @dataDir nvarchar(4000) = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS nvarchar(4000));
DECLARE @logDir  nvarchar(4000) = CAST(SERVERPROPERTY('InstanceDefaultLogPath')  AS nvarchar(4000));

DECLARE @sql nvarchar(max) =
      N'RESTORE DATABASE ' + QUOTENAME(@db) + N' FROM DISK = N''' + REPLACE(@bak, '''', '''''') + N''' WITH '
    + N'MOVE ''WWI_Primary''       TO N''' + @dataDir + @db + N'_Primary.mdf'', '
    + N'MOVE ''WWI_UserData''      TO N''' + @dataDir + @db + N'_UserData.ndf'', '
    + N'MOVE ''WWI_Log''           TO N''' + @logDir  + @db + N'_Log.ldf'', '
    + N'MOVE ''WWI_InMemory_Data'' TO N''' + @dataDir + @db + N'_InMemory_Data'', '
    + N'RECOVERY, STATS = 5'
    + CASE WHEN @replace = 1 THEN N', REPLACE' ELSE N'' END
    + N';';

PRINT @sql;
EXEC sys.sp_executesql @sql;
"@

Invoke-DemoSqlQuery -Context $ctx -Variables @{ BackupPath = $BackupPath; DbName = $Database; Replace = $replace } -Query $restoreSql

Write-Host "[OK]  Restore of '$Database' complete." -ForegroundColor Green
Write-Host 'Next: run scripts/sql/00-verify-wideworldimporters.sql then 01-enable-query-store.sql' -ForegroundColor Yellow
