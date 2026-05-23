<#
.SYNOPSIS
    Installs system-diagnostics.ps1 to a local folder on PATH so it can
    be invoked from any project directory.

.DESCRIPTION
    Copies system-diagnostics.ps1 (and optionally app-diagnostics.ps1)
    to the chosen folder, creating it if needed, and appends the folder
    to the user-scope PATH variable if not already present.

    After running this once, open a new PowerShell window and:
        system-diagnostics.ps1 -ProjectName 'whatever'

.PARAMETER Destination
    Folder to copy scripts into. Default: %USERPROFILE%\bin.

.PARAMETER IncludeAppDiagnostics
    Also copy app-diagnostics.ps1 (Media-Inventory-specific). Off by
    default because that script only makes sense in the System-tools
    project.

.PARAMETER NoPath
    Skip the PATH update.
#>

[CmdletBinding()]
param(
    [string]$Destination = (Join-Path $env:USERPROFILE 'bin'),
    [switch]$IncludeAppDiagnostics,
    [switch]$NoPath
)

$ErrorActionPreference = 'Stop'

$src = $PSScriptRoot
if (-not $src) { $src = (Get-Location).Path }

if (-not (Test-Path $Destination)) {
    Write-Host "Creating $Destination"
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
}

$files = @('system-diagnostics.ps1')
if ($IncludeAppDiagnostics) {
    $files += 'app-diagnostics.ps1'
    foreach ($helper in '_dx_db_check.py','_dx_lookup_check.py') {
        if (Test-Path (Join-Path $src $helper)) { $files += $helper }
    }
}

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
