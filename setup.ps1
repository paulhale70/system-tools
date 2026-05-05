<#
.SYNOPSIS
    Bootstraps the Media Inventory Scanner on a fresh Windows machine.

.DESCRIPTION
    Installs Python and Git via winget if missing, clones (or updates) the
    repo, installs Python dependencies, and optionally restores a backed-up
    media_inventory.db. Designed to be run on a brand-new laptop.

    Run from an elevated or normal PowerShell prompt:
        powershell -ExecutionPolicy Bypass -File .\setup.ps1

.PARAMETER InstallDir
    Where to clone the repo. Defaults to %USERPROFILE%\System-tools.

.PARAMETER RepoUrl
    Git URL of the repo.

.PARAMETER RestoreDb
    Path to a media_inventory.db backup to copy into %USERPROFILE%.
#>

[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:USERPROFILE 'System-tools'),
    [string]$RepoUrl    = 'https://github.com/paulhale70/System-tools.git',
    [string]$RestoreDb
)

$ErrorActionPreference = 'Stop'

function Write-Step($msg) {
    Write-Host ''
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function Have-Cmd($name) {
    [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Ensure-Winget {
    if (-not (Have-Cmd winget)) {
        throw "winget not found. Install 'App Installer' from the Microsoft Store, then re-run this script."
    }
}

function Install-WithWinget($id, $friendlyName) {
    Write-Step "Installing $friendlyName ($id)"
    winget install --id $id --exact --silent --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
        # -1978335189 = APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED
        throw "winget failed for $id (exit $LASTEXITCODE)."
    }
}

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable('Path','Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path','User')
    $env:Path = "$machine;$user"
}

# ---------------------------------------------------------------------------
# 1. Python
# ---------------------------------------------------------------------------
Ensure-Winget

if (Have-Cmd python) {
    Write-Step "Python already installed: $((& python --version) 2>&1)"
} else {
    Install-WithWinget 'Python.Python.3.12' 'Python 3.12'
    Refresh-Path
    if (-not (Have-Cmd python)) {
        throw "Python install completed but 'python' is still not on PATH. Open a new terminal and re-run."
    }
}

# ---------------------------------------------------------------------------
# 2. Git
# ---------------------------------------------------------------------------
if (Have-Cmd git) {
    Write-Step "Git already installed: $((& git --version) 2>&1)"
} else {
    Install-WithWinget 'Git.Git' 'Git'
    Refresh-Path
    if (-not (Have-Cmd git)) {
        throw "Git install completed but 'git' is still not on PATH. Open a new terminal and re-run."
    }
}

# ---------------------------------------------------------------------------
# 3. Clone or update the repo
# ---------------------------------------------------------------------------
if (Test-Path (Join-Path $InstallDir '.git')) {
    Write-Step "Updating existing checkout at $InstallDir"
    git -C $InstallDir pull --ff-only
} else {
    Write-Step "Cloning $RepoUrl -> $InstallDir"
    $parent = Split-Path $InstallDir -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    git clone $RepoUrl $InstallDir
}

# ---------------------------------------------------------------------------
# 4. Python dependencies
# ---------------------------------------------------------------------------
Write-Step 'Upgrading pip'
python -m pip install --upgrade pip

Write-Step 'Installing requirements.txt'
python -m pip install -r (Join-Path $InstallDir 'requirements.txt')

# ---------------------------------------------------------------------------
# 5. Optional database restore
# ---------------------------------------------------------------------------
if ($RestoreDb) {
    if (-not (Test-Path $RestoreDb)) {
        throw "RestoreDb path not found: $RestoreDb"
    }
    $dest = Join-Path $env:USERPROFILE 'media_inventory.db'
    if (Test-Path $dest) {
        $backup = "$dest.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Write-Step "Backing up existing DB to $backup"
        Copy-Item $dest $backup -Force
    }
    Write-Step "Restoring database from $RestoreDb -> $dest"
    Copy-Item $RestoreDb $dest -Force
}

# ---------------------------------------------------------------------------
# 6. Done
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'Setup complete.' -ForegroundColor Green
Write-Host "Project:   $InstallDir"
Write-Host "Launch:    double-click run.bat, or run 'python main.py' from $InstallDir"
