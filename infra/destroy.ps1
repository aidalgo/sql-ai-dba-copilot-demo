<#
.SYNOPSIS
    Destroys the demo by deleting its resource group.

.DESCRIPTION
    Deletes the entire resource group created by deploy.ps1. This removes ALL
    resources (both VMs, disks, network, public IP) and stops all billing for
    them. There is no undo.

.PARAMETER ResourceGroup
    Name of the resource group to delete.

.PARAMETER Force
    Skip the interactive confirmation prompt.

.EXAMPLE
    ./destroy.ps1 -ResourceGroup rg-wwi-aidemo

.NOTES
    Requires the Azure CLI (az) and an authenticated session (az login).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI (az) is not installed or not on PATH.'
}

$exists = az group exists --name $ResourceGroup | ConvertFrom-Json
if (-not $exists) {
    Write-Host "Resource group '$ResourceGroup' does not exist. Nothing to do." -ForegroundColor Yellow
    return
}

if (-not $Force) {
    Write-Host "This will PERMANENTLY DELETE resource group '$ResourceGroup' and ALL resources in it." -ForegroundColor Red
    $confirm = Read-Host "Type the resource group name to confirm"
    if ($confirm -ne $ResourceGroup) {
        Write-Host 'Confirmation did not match. Aborting.' -ForegroundColor Yellow
        return
    }
}

Write-Host "Deleting resource group '$ResourceGroup'..." -ForegroundColor Cyan
az group delete --name $ResourceGroup --yes --no-wait
Write-Host "Delete initiated (running asynchronously). Check the portal or 'az group list' for status." -ForegroundColor Green
