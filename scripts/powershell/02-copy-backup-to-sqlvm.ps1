<#
.SYNOPSIS
    Copies the WideWorldImporters .bak from the jumpbox to the SQL VM.

.DESCRIPTION
    Optional helper for the case where you downloaded the backup on the jumpbox
    and want to push it to the SQL VM so SQL Server can read it from a local
    path. Uses PowerShell Remoting (WinRM) over the private VNet.

    Simplest alternative: RDP/connect directly to the SQL VM and run
    01-download-wideworldimporters.ps1 there, avoiding this copy entirely.

.PARAMETER SqlVmHost
    Private IP or hostname of the SQL VM (e.g. 10.20.2.10).

.PARAMETER Credential
    Credentials for a local admin on the SQL VM. If omitted you are prompted.

.PARAMETER SourcePath
    Local path to the .bak on the jumpbox.

.PARAMETER DestinationPath
    Target path on the SQL VM (must be readable by the SQL Server service account).

.EXAMPLE
    ./02-copy-backup-to-sqlvm.ps1 -SqlVmHost 10.20.2.10 `
        -SourcePath .\downloads\WideWorldImporters-Full.bak `
        -DestinationPath 'C:\SqlBackups\WideWorldImporters-Full.bak'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SqlVmHost,
    [Parameter(Mandatory)][string]$SourcePath,
    [string]$DestinationPath = 'C:\SqlBackups\WideWorldImporters-Full.bak',
    [System.Management.Automation.PSCredential]$Credential
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $SourcePath)) {
    throw "Source backup not found: $SourcePath. Run 01-download-wideworldimporters.ps1 first."
}

if (-not $Credential) {
    $Credential = Get-Credential -Message "Local admin credentials for SQL VM $SqlVmHost"
}

Write-Host "[INFO] Opening remoting session to $SqlVmHost ..." -ForegroundColor Cyan
$session = New-PSSession -ComputerName $SqlVmHost -Credential $Credential -ErrorAction Stop
try {
    $destDir = Split-Path -Parent $DestinationPath
    Invoke-Command -Session $session -ScriptBlock {
        param($dir)
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    } -ArgumentList $destDir

    Write-Host "[INFO] Copying backup to $($SqlVmHost):$DestinationPath ..." -ForegroundColor Cyan
    Copy-Item -Path $SourcePath -Destination $DestinationPath -ToSession $session -Force

    $remoteSize = Invoke-Command -Session $session -ScriptBlock {
        param($p) (Get-Item $p).Length
    } -ArgumentList $DestinationPath
    Write-Host "[OK]  Copied $([math]::Round($remoteSize/1MB,1)) MB to the SQL VM." -ForegroundColor Green
}
finally {
    Remove-PSSession $session
}

Write-Host 'Next: 03-restore-wideworldimporters.ps1 (run against the SQL VM)' -ForegroundColor Yellow
