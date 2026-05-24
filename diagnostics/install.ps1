<#
.SYNOPSIS
    Installs the generic diagnostic scripts to a local folder on PATH
    so they can be invoked from any project directory.

.DESCRIPTION
    Copies system-diagnostics.ps1, diff-diagnostics.ps1, and
    trends-diagnostics.ps1 from this folder to the chosen destination,
    creating it if needed, and appends the folder to the user-scope
    PATH variable.

    After running once, open a new PowerShell window and:
        system-diagnostics.ps1 -ProjectName 'whatever'

    Project-specific wrappers like app-diagnostics.ps1 live with their
    project (e.g. media-inventory/) and are not installed globally.

.PARAMETER Destination
    Folder to copy scripts into. Default: %USERPROFILE%\bin.

.PARAMETER NoPath
    Skip the PATH update.
#>

[CmdletBinding()]
param(
    [string]$Destination = (Join-Path $env:USERPROFILE 'bin'),
    [switch]$NoPath
)

$ErrorActionPreference = 'Stop'

$src = $PSScriptRoot
if (-not $src) { $src = (Get-Location).Path }

if (-not (Test-Path $Destination)) {
    Write-Host "Creating $Destination"
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
}

$files = @(
    'system-diagnostics.ps1',
    'diff-diagnostics.ps1',
    'trends-diagnostics.ps1'
)

foreach ($f in $files) {
    $source = Join-Path $src $f
    if (-not (Test-Path $source)) {
        Write-Warning "Source not found: $source"
        continue
    }
    Copy-Item $source (Join-Path $Destination $f) -Force
    Write-Host "  Copied $f -> $Destination"
}

if (-not $NoPath) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = ($userPath -split ';') | Where-Object { $_ }
    if ($entries -notcontains $Destination) {
        $newPath = ($entries + $Destination) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Write-Host "Added $Destination to user PATH (open a new terminal to pick it up)."
    } else {
        Write-Host "$Destination already on user PATH."
    }
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
Write-Host 'Open a new PowerShell window and try: system-diagnostics.ps1'
