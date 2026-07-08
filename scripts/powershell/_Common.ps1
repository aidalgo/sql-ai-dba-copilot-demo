<#
.SYNOPSIS
    Shared helpers for the demo PowerShell scripts (dot-source this file).

.DESCRIPTION
    Provides a thin wrapper over sqlcmd.exe so every script connects the same
    way. sqlcmd ships with SSMS / the SQL command-line tools, so it is reliably
    present on the jumpbox. Windows or SQL authentication is supported.

    Usage from another script:
        . "$PSScriptRoot/_Common.ps1"
        $conn = New-DemoSqlContext -ServerInstance '10.20.2.10' -Database 'WideWorldImporters' -SqlLogin 'demodba' -SqlPassword $secure
        Invoke-DemoSqlFile -Context $conn -InputFile './x.sql' -Variables @{ Year = 2015 }
#>

Set-StrictMode -Version Latest

function Test-DemoSqlcmd {
    <# Returns $true if sqlcmd is available on PATH. #>
    return [bool](Get-Command sqlcmd -ErrorAction SilentlyContinue)
}

function New-DemoSqlContext {
    <#
    .SYNOPSIS
        Builds a connection context object used by the Invoke-Demo* helpers.
    .PARAMETER UseWindowsAuth
        Use integrated (Windows) authentication. On standalone Azure VMs without
        a shared domain this only works when connecting to the local instance.
        For the jumpbox -> SQL VM hop, use SQL authentication.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ServerInstance,
        [string]$Database = 'WideWorldImporters',
        [string]$SqlLogin,
        [System.Security.SecureString]$SqlPassword,
        [switch]$UseWindowsAuth,
        [int]$LoginTimeoutSeconds = 15
    )

    if (-not $UseWindowsAuth) {
        if ([string]::IsNullOrWhiteSpace($SqlLogin) -or -not $SqlPassword) {
            throw 'SQL authentication requires -SqlLogin and -SqlPassword (or pass -UseWindowsAuth).'
        }
    }

    return [pscustomobject]@{
        ServerInstance      = $ServerInstance
        Database            = $Database
        SqlLogin            = $SqlLogin
        SqlPassword         = $SqlPassword
        UseWindowsAuth      = [bool]$UseWindowsAuth
        LoginTimeoutSeconds = $LoginTimeoutSeconds
    }
}

function Get-DemoSqlcmdArgs {
    param([Parameter(Mandatory)][object]$Context)

    $a = @('-S', $Context.ServerInstance, '-d', $Context.Database,
        '-l', "$($Context.LoginTimeoutSeconds)", '-b')   # -b: exit with error on SQL error
    if ($Context.UseWindowsAuth) {
        $a += '-E'
    }
    else {
        $a += @('-U', $Context.SqlLogin)   # password is passed via $env:SQLCMDPASSWORD, never on the command line
    }
    return , $a
}

function Invoke-DemoSqlcmd {
    <# Internal: runs sqlcmd with the given extra args, handling the password env var. #>
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string[]]$ExtraArgs
    )
    if (-not (Test-DemoSqlcmd)) {
        throw 'sqlcmd was not found on PATH. Install the SQL command-line tools (bundled with SSMS) and retry.'
    }

    $args = (Get-DemoSqlcmdArgs -Context $Context) + $ExtraArgs
    $restore = $false
    try {
        if (-not $Context.UseWindowsAuth) {
            $env:SQLCMDPASSWORD = [System.Net.NetworkCredential]::new('', $Context.SqlPassword).Password
            $restore = $true
        }
        & sqlcmd @args
        if ($LASTEXITCODE -ne 0) {
            throw "sqlcmd exited with code $LASTEXITCODE."
        }
    }
    finally {
        if ($restore) { Remove-Item Env:SQLCMDPASSWORD -ErrorAction SilentlyContinue }
    }
}

function ConvertTo-DemoSqlcmdVars {
    param([hashtable]$Variables)
    $out = @()
    if ($Variables) {
        foreach ($k in $Variables.Keys) {
            $out += @('-v', "$k=$($Variables[$k])")
        }
    }
    return , $out
}

function Invoke-DemoSqlFile {
    <# Runs a .sql file. Optional -Variables become sqlcmd :setvar values. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$InputFile,
        [hashtable]$Variables
    )
    if (-not (Test-Path $InputFile)) { throw "SQL file not found: $InputFile" }
    $extra = @('-i', $InputFile) + (ConvertTo-DemoSqlcmdVars -Variables $Variables)
    Invoke-DemoSqlcmd -Context $Context -ExtraArgs $extra
}

function Invoke-DemoSqlQuery {
    <# Runs an inline T-SQL query string. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$Query,
        [hashtable]$Variables
    )
    $extra = @('-Q', $Query) + (ConvertTo-DemoSqlcmdVars -Variables $Variables)
    Invoke-DemoSqlcmd -Context $Context -ExtraArgs $extra
}
