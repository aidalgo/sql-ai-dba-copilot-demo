<#
.SYNOPSIS
    Downloads the WideWorldImporters sample backup (.bak).

.DESCRIPTION
    Downloads WideWorldImporters-Full.bak from the official Microsoft
    sql-server-samples GitHub release. The file is ~120 MB compressed and
    restores to roughly 3 GB. Idempotent: skips the download if the file already
    exists and is non-empty (use -Force to re-download).

    Run this on whichever machine will hold the backup before restore. In this
    demo we download on the SQL VM (or download on the jumpbox then copy with
    02-copy-backup-to-sqlvm.ps1).

.PARAMETER DestinationPath
    Full path for the .bak file. Defaults to .\downloads\WideWorldImporters-Full.bak
    relative to the repo root.

.EXAMPLE
    ./01-download-wideworldimporters.ps1 -DestinationPath C:\SqlBackups\WideWorldImporters-Full.bak
#>
[CmdletBinding()]
param(
    [string]$DestinationPath,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Official, stable release asset (works on SQL Server 2016 SP1 and later).
$BackupUrl = 'https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImporters-Full.bak'

if (-not $DestinationPath) {
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
    $DestinationPath = Join-Path $repoRoot 'downloads' 'WideWorldImporters-Full.bak'
}

$destDir = Split-Path -Parent $DestinationPath
if (-not (Test-Path $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
}

if ((Test-Path $DestinationPath) -and -not $Force) {
    $size = (Get-Item $DestinationPath).Length
    if ($size -gt 0) {
        Write-Host "[SKIP] Backup already present: $DestinationPath ($([math]::Round($size/1MB,1)) MB). Use -Force to re-download." -ForegroundColor Yellow
        return
    }
}

Write-Host "[INFO] Downloading WideWorldImporters backup..." -ForegroundColor Cyan
Write-Host "       From: $BackupUrl"
Write-Host "       To:   $DestinationPath"

$oldProgress = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'   # dramatically speeds up Invoke-WebRequest for large files
try {
    Invoke-WebRequest -Uri $BackupUrl -OutFile $DestinationPath -UseBasicParsing
}
finally {
    $ProgressPreference = $oldProgress
}

$size = (Get-Item $DestinationPath).Length
Write-Host "[OK]  Downloaded $([math]::Round($size/1MB,1)) MB." -ForegroundColor Green
Write-Host 'Next: 02-copy-backup-to-sqlvm.ps1 (if downloaded on the jumpbox) or 03-restore-wideworldimporters.ps1' -ForegroundColor Yellow
