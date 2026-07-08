<#
.SYNOPSIS
    Deploys the SQL Server + AI DBA Copilot demo infrastructure to Azure.

.DESCRIPTION
    Creates a resource group (if needed) and deploys infra/main.bicep.
    Prompts securely for the VM admin password and the SQL auth password so
    secrets never need to live in a parameters file.

    This is a DEMO deployment. Review infra/main.bicep and the README before running.

.PARAMETER ResourceGroup
    Name of the resource group to deploy into (created if it does not exist).

.PARAMETER Location
    Azure region, e.g. "eastus2".

.PARAMETER ParametersFile
    Path to a parameters JSON file. Defaults to infra/parameters.json if present,
    otherwise infra/parameters.example.json. Copy the example to parameters.json
    and edit it (parameters.json is gitignored).

.EXAMPLE
    ./deploy.ps1 -ResourceGroup rg-wwi-aidemo -Location eastus2

.NOTES
    Requires the Azure CLI (az) and an authenticated session (az login).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$Location,

    [Parameter(Mandatory = $false)]
    [string]$ParametersFile
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$bicepFile = Join-Path $scriptRoot 'main.bicep'

# Resolve the parameters file: prefer a local (gitignored) parameters.json.
if (-not $ParametersFile) {
    $local = Join-Path $scriptRoot 'parameters.json'
    $example = Join-Path $scriptRoot 'parameters.example.json'
    $ParametersFile = (Test-Path $local) ? $local : $example
}
Write-Host "Using parameters file: $ParametersFile" -ForegroundColor Cyan

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI (az) is not installed or not on PATH. See https://learn.microsoft.com/cli/azure/install-azure-cli'
}

# Confirm we are logged in.
$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    throw 'Not logged in to Azure. Run "az login" first.'
}
Write-Host "Subscription: $($account.name) ($($account.id))" -ForegroundColor Cyan

# Ensure the resource providers this template needs are registered. NOTE:
# 'az deployment group validate' does NOT verify this, but 'create' fails at
# preflight (MissingSubscriptionRegistration) if a provider is not registered.
# Microsoft.SqlVirtualMachine in particular is often NotRegistered on new subs.
$requiredProviders = @('Microsoft.Compute', 'Microsoft.Network', 'Microsoft.SqlVirtualMachine')
foreach ($rp in $requiredProviders) {
    $state = az provider show --namespace $rp --query registrationState -o tsv 2>$null
    if ($state -ne 'Registered') {
        Write-Host "Registering resource provider $rp (currently '$state')..." -ForegroundColor Cyan
        az provider register --namespace $rp --output none 2>$null
    }
}
foreach ($rp in $requiredProviders) {
    $state = az provider show --namespace $rp --query registrationState -o tsv 2>$null
    for ($i = 0; $i -lt 30 -and $state -ne 'Registered'; $i++) {
        Start-Sleep -Seconds 10
        $state = az provider show --namespace $rp --query registrationState -o tsv 2>$null
    }
    if ($state -ne 'Registered') {
        throw "Resource provider $rp is '$state', not 'Registered'. Wait and retry, or run: az provider register --namespace $rp --wait"
    }
}
Write-Host 'Required resource providers are registered.' -ForegroundColor Cyan

# Prompt securely for the two passwords (not stored in any file).
$adminPwd = Read-Host -AsSecureString 'Enter the VM local admin password (min 12 chars, complex)'
$sqlPwd = Read-Host -AsSecureString 'Enter the SQL auth login password (min 12 chars, complex)'
$adminPwdPlain = [System.Net.NetworkCredential]::new('', $adminPwd).Password
$sqlPwdPlain = [System.Net.NetworkCredential]::new('', $sqlPwd).Password

# Fail fast with a clear message if a password is too short. ARM requires >= 12
# and rejects the whole deployment at preflight otherwise (an error the Azure CLI
# bug would then hide). Azure also requires complexity: 3 of 4 of upper/lower/
# digit/special, and the password must not contain the username.
foreach ($p in @(@{ n = 'VM admin'; v = $adminPwdPlain }, @{ n = 'SQL auth'; v = $sqlPwdPlain })) {
    if ([string]::IsNullOrEmpty($p.v) -or $p.v.Length -lt 12) {
        throw "The $($p.n) password is $(("$($p.v)").Length) characters. Azure requires at least 12 (upper+lower+digit+special). Re-run and enter a longer, complex password."
    }
}

Write-Host "Ensuring resource group '$ResourceGroup' in '$Location'..." -ForegroundColor Cyan
az group create --name $ResourceGroup --location $Location --output none

# Build a TEMP parameters file that merges the base parameters with the two
# secrets. Passing secrets via a JSON file (not inline "key=value") avoids every
# shell/CLI tokenization edge case - spaces, quotes, '@', '=' in a password - that
# can silently truncate a value and trip ARM's minLength check. The file is
# locked down to the current user where possible and ALWAYS deleted afterward.
$baseParams = Get-Content -Raw -Path $ParametersFile | ConvertFrom-Json
if (-not $baseParams.parameters) {
    $baseParams | Add-Member -NotePropertyName parameters -NotePropertyValue ([pscustomobject]@{})
}
$baseParams.parameters | Add-Member -NotePropertyName adminPassword   -NotePropertyValue ([pscustomobject]@{ value = $adminPwdPlain }) -Force
$baseParams.parameters | Add-Member -NotePropertyName sqlAuthPassword -NotePropertyValue ([pscustomobject]@{ value = $sqlPwdPlain })  -Force

$tempParams = Join-Path ([System.IO.Path]::GetTempPath()) ("wwi-params-{0}.json" -f ([guid]::NewGuid().ToString('N')))
$baseParams | ConvertTo-Json -Depth 20 | Set-Content -Path $tempParams -Encoding utf8
try {
    if ($IsWindows) { icacls $tempParams /inheritance:r /grant:r "$($env:USERNAME):(R,W)" *> $null }
    else { chmod 600 $tempParams }
}
catch { }

# Clear plaintext secrets from memory now that they live only in the temp file.
$adminPwdPlain = $null
$sqlPwdPlain = $null

$deploymentName = "wwi-aidemo-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$deployStartUtc = (Get-Date).ToUniversalTime().AddMinutes(-1).ToString('yyyy-MM-ddTHH:mm:ssZ')
Write-Host "Starting deployment '$deploymentName' (this can take 10-20 min)..." -ForegroundColor Cyan

# Run the deployment. We deliberately do NOT capture/parse stdout here: some
# Azure CLI versions throw "The content for this response was already consumed"
# while formatting an error, which hides the real cause and would break parsing.
# Instead we check the exit code, then fetch outputs/errors with separate
# read-only commands that are not affected by that bug. The temp params file is
# removed in the finally block whether the deployment succeeds or fails.
try {
    az deployment group create `
        --name $deploymentName `
        --resource-group $ResourceGroup `
        --template-file $bicepFile `
        --parameters $tempParams `
        --output none
    $deployExit = $LASTEXITCODE
}
finally {
    Remove-Item -Path $tempParams -Force -ErrorAction SilentlyContinue
}

# IMPORTANT: do not trust the exit code alone. The Azure CLI 2.77.0 "content
# already consumed" bug can make az exit NON-ZERO even when the deployment
# SUCCEEDED (it fails while formatting the final output). So check the actual
# deployment provisioningState. Empty => the deployment was never registered
# (a preflight failure), which we treat as a failure below.
$deployState = az deployment group show `
    --resource-group $ResourceGroup `
    --name $deploymentName `
    --query properties.provisioningState `
    --output tsv 2>$null
if ([string]::IsNullOrWhiteSpace($deployState)) { $deployState = 'NotRegistered' }
if ($deployExit -ne 0 -and $deployState -eq 'Succeeded') {
    Write-Host "(Azure CLI exited $deployExit while formatting output, but the deployment actually Succeeded - continuing.)" -ForegroundColor DarkYellow
}

if ($deployState -ne 'Succeeded') {
    Write-Host ''
    Write-Host "Deployment '$deploymentName' did not succeed (state: $deployState, az exit code $deployExit)." -ForegroundColor Red
    Write-Host 'The Azure CLI may have printed "The content for this response was already consumed"' -ForegroundColor DarkYellow
    Write-Host 'instead of the real error. Retrieving the real error(s)...' -ForegroundColor DarkYellow
    Write-Host ''

    # (a) Server-side (resource) failures register deployment operations we can read back.
    $opErrors = az deployment operation group list `
        --resource-group $ResourceGroup `
        --name $deploymentName `
        --query "[?properties.provisioningState=='Failed'].properties.statusMessage" `
        --output json 2>$null
    if ($opErrors -and $opErrors.Trim() -ne '[]') {
        Write-Host 'Resource-level error(s):' -ForegroundColor Yellow
        Write-Host $opErrors
    }

    # (b) Preflight failures never register a deployment; the real cause (policy
    #     deny, password/InvalidTemplate, SkuNotAvailable, unregistered RP, ...)
    #     is recorded in the subscription Activity Log.
    $logErrors = az monitor activity-log list `
        --resource-group $ResourceGroup `
        --start-time $deployStartUtc `
        --query "[?status.value=='Failed'].properties.statusMessage" `
        --output tsv 2>$null
    if ($logErrors) {
        Write-Host 'Real error(s) from the Activity Log:' -ForegroundColor Yellow
        $logErrors -split "`n" | Where-Object { $_ } | Select-Object -Unique | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    }
    elseif (-not ($opErrors -and $opErrors.Trim() -ne '[]')) {
        Write-Host 'No failure detail is available yet (the Activity Log can lag a few seconds).' -ForegroundColor Yellow
        Write-Host 'Re-check with:' -ForegroundColor Yellow
        Write-Host ("  az monitor activity-log list -g {0} --start-time {1} --query `"[?status.value=='Failed'].properties.statusMessage`" -o tsv" -f $ResourceGroup, $deployStartUtc) -ForegroundColor Yellow
    }
    throw "Deployment '$deploymentName' failed. See the real error(s) above."
}

# Fetch outputs with a separate read-only call (robust against the CLI output bug).
$outputsJson = az deployment group show `
    --resource-group $ResourceGroup `
    --name $deploymentName `
    --query properties.outputs `
    --output json
$o = $outputsJson | ConvertFrom-Json

Write-Host ''
Write-Host '==================== Deployment complete ====================' -ForegroundColor Green
Write-Host ("Jumpbox FQDN (RDP here):   {0}" -f $o.jumpboxFqdn.value)
Write-Host ("Jumpbox public IP:         {0}" -f $o.jumpboxPublicIp.value)
Write-Host ("SQL VM private IP (SSMS):  {0}" -f $o.sqlServerPrivateIp.value)
Write-Host ("SQL VM computer name:      {0}" -f $o.sqlServerComputerName.value)
Write-Host ("SQL auth login:            {0}" -f $o.sqlAuthLoginName.value)
Write-Host '============================================================='
Write-Host 'Next: RDP into the jumpbox, install/validate SSMS + the Copilot component,' -ForegroundColor Yellow
Write-Host 'sign in with an individual GitHub Copilot account, then connect SSMS to the' -ForegroundColor Yellow
Write-Host ('SQL VM at {0} (login demodba). See README.md.' -f $o.sqlServerPrivateIp.value) -ForegroundColor Yellow
