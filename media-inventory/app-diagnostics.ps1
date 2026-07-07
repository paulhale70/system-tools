<#
.SYNOPSIS
    Media Inventory Scanner full diagnostic collector.

.DESCRIPTION
    Runs the generic Windows diagnostics from system-diagnostics.ps1
    and then adds Media-Inventory-specific sections: SQLite DB health,
    application log capture, and an end-to-end lookup pipeline test.
    Writes a consolidated SUMMARY.txt with green/yellow/red verdicts,
    zips everything, and opens the report folder.

    Run from the project folder:
        powershell -ExecutionPolicy Bypass -File .\app-diagnostics.ps1

.PARAMETER OutputRoot
    Directory where the report folder and zip are written. Default: Desktop.

.PARAMETER EventLogDays
    Days of Application/System event log entries to collect. Default: 7.

.PARAMETER Sanitize
    Redact PII from text files before zipping. Useful when sharing the
    report outside your team.

.PARAMETER IncludeMiniDumps
    Copy C:\Windows\Minidump\*.dmp into the bundle (can be large).

.PARAMETER CaptureNetSeconds
    Run 'netsh trace' for the given number of seconds and bundle the
    resulting .etl. Off when 0 (default). Requires elevation.

.PARAMETER PerfSampleSeconds
    Task-Manager-style performance sample duration in seconds
    (CPU / memory / disk / network counters + top-30 processes by
    CPU delta). Default: 5. Pass 0 to skip.

.PARAMETER AnalyzeKernelDump
    Also run WinDbg !analyze -v against C:\Windows\MEMORY.DMP.
    Off by default (slow).
#>

[CmdletBinding()]
param(
    [string]$OutputRoot      = [Environment]::GetFolderPath('Desktop'),
    [int]$EventLogDays       = 7,
    [switch]$Sanitize,
    [switch]$IncludeMiniDumps,
    [int]$CaptureNetSeconds  = 0,
    [int]$PerfSampleSeconds  = 5,
    [switch]$AnalyzeKernelDump
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

# Load system-diagnostics.ps1 as a library (functions only, no auto-run).
# system-diagnostics lives in ../diagnostics/ after the repo reorganization.
. (Join-Path $PSScriptRoot '..\diagnostics\system-diagnostics.ps1')

$endpoints = @(
    'https://api.upcitemdb.com/prod/trial/lookup?upc=000000000000'
    'https://www.googleapis.com/books/v1/volumes?q=isbn:9780000000000'
    'https://openlibrary.org/api/books?bibkeys=ISBN:9780000000000&format=json'
    'https://musicbrainz.org/ws/2/release/?query=barcode:000000000000&fmt=json'
)

$reportDir = Initialize-Report -OutputRoot $OutputRoot -ProjectName 'MediaInventory'
Invoke-SystemDiagnostics -ReportDir $reportDir -EventLogDays $EventLogDays `
    -Endpoints $endpoints -WerKeywords 'python|pythonw|main\.py|media_inventory' `
    -IncludeMiniDumps:$IncludeMiniDumps -CaptureNetSeconds $CaptureNetSeconds `
    -PerfSampleSeconds $PerfSampleSeconds -AnalyzeKernelDump:$AnalyzeKernelDump

# ---------------------------------------------------------------------------
# App-specific sections
# ---------------------------------------------------------------------------

$script:appResolvedDb = $null

# 4. SQLite database (resolved path, integrity, row counts)
Write-Section '4. SQLite database'
Try-Run 'Database info' {
    $appRoot = $PSScriptRoot   # app helpers live alongside this script
    $configPath = Join-Path $env:USERPROFILE '.media_inventory_config.json'
    $report = New-Object System.Text.StringBuilder

    $envDbVal = if ([string]::IsNullOrEmpty($env:MEDIA_INVENTORY_DB)) { '(unset)' } else { $env:MEDIA_INVENTORY_DB }
    $null = $report.AppendLine("MEDIA_INVENTORY_DB env var: $envDbVal")
    $null = $report.AppendLine("Config file: $configPath  (exists: $(Test-Path $configPath))")
    if (Test-Path $configPath) {
        $null = $report.AppendLine('--- config contents ---')
        $null = $report.AppendLine((Get-Content $configPath -Raw))
        Copy-Item $configPath (Join-Path $reportDir '04-config.json') -Force
    }

    $resolvedDb = $null
    $helper = if ($appRoot) { Join-Path $appRoot '_dx_db_check.py' } else { $null }
    if ($helper -and (Test-Path $helper) -and (Test-Path (Join-Path $appRoot 'database.py'))) {
        $r = Invoke-PythonScript $appRoot $helper
        $null = $report.AppendLine('--- python database.py resolution ---')
        $null = $report.AppendLine($r.Output)
        if ($r.Output -match 'RESOLVED:\s*(.+)') { $resolvedDb = $Matches[1].Trim() }

        if ($r.Output -match 'INTEGRITY:\s*ok' -and $r.Output -match 'QUICK:\s*ok') {
            Add-Summary 'OK' "DB integrity ok at $resolvedDb"
        } elseif ($r.Output -match 'INTEGRITY:') {
            Add-Summary 'FAIL' 'DB integrity check returned errors (see 04-database.txt).'
        } elseif ($r.Output -match 'EXISTS:\s*False') {
            Add-Summary 'WARN' "DB does not exist yet at $resolvedDb (will be created on first launch)."
        } else {
            Add-Summary 'WARN' 'DB integrity could not be determined; see 04-database.txt.'
        }
    } else {
        $null = $report.AppendLine('database.py not reachable from working directory; using fallback default.')
        $resolvedDb = Join-Path $env:USERPROFILE 'media_inventory.db'
        Add-Summary 'WARN' 'Run app-diagnostics.ps1 from the project folder for full DB diagnostics.'
    }

    if ($resolvedDb -and (Test-Path $resolvedDb)) {
        $f = Get-Item $resolvedDb
        $info = [PSCustomObject]@{
            Path          = $f.FullName
            SizeBytes     = $f.Length
            SizeMB        = [math]::Round($f.Length/1MB, 3)
            LastWriteTime = $f.LastWriteTime
            CreationTime  = $f.CreationTime
            SHA256        = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
            Attributes    = $f.Attributes.ToString()
        }
        $null = $report.AppendLine('--- file info ---')
        $null = $report.AppendLine(($info | Format-List | Out-String))

        $rawAttr = [int]$f.Attributes
        if (($rawAttr -band 0x400000) -or ($rawAttr -band 0x40000)) {
            Add-Summary 'FAIL' "DB file is a cloud placeholder (not fully downloaded): $resolvedDb"
        }
    }

    $script:appResolvedDb = $resolvedDb
    Save-Text '04-database.txt' $report.ToString()
}

# 8b. Application log
Write-Section '8b. Application log'
Try-Run 'App log' {
    $candidates = @()
    if ($script:appResolvedDb) {
        $candidates += (Join-Path (Split-Path $script:appResolvedDb -Parent) 'media_inventory.log')
    }
    $candidates += (Join-Path $env:USERPROFILE 'media_inventory.log')
    $logPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($logPath) {
        Copy-Item $logPath (Join-Path $reportDir '08-app.log') -Force
        Get-ChildItem -Path (Split-Path $logPath -Parent) -Filter 'media_inventory.log.*' -ErrorAction SilentlyContinue |
            ForEach-Object { Copy-Item $_.FullName (Join-Path $reportDir ("08-app." + $_.Name.Split('.')[-1] + '.log')) -Force }
        $bytes = (Get-Item $logPath).Length
        Add-Summary 'OK' ("Captured app log ($([math]::Round($bytes/1KB,1)) KB) from $logPath")
    } else {
        'No media_inventory.log found alongside the DB or in %USERPROFILE%.' |
            Set-Content (Join-Path $reportDir '08-app.log')
        Add-Summary 'WARN' 'No application log found (app may not have been launched yet).'
    }
}

# 9. End-to-end lookup pipeline test
Write-Section '9. Lookup pipeline test'
Try-Run 'Lookup pipeline' {
    $appRoot = $PSScriptRoot   # app helpers live alongside this script
    $helper = if ($appRoot) { Join-Path $appRoot '_dx_lookup_check.py' } else { $null }
    if ($helper -and (Test-Path $helper) -and (Test-Path (Join-Path $appRoot 'lookup.py'))) {
        $r = Invoke-PythonScript $appRoot $helper
        Save-Text '09-lookup.txt' $r.Output
        if ($r.Output -match '"title"') {
            Add-Summary 'OK' 'Lookup pipeline returned a result for the known-good UPC.'
        } elseif ($r.Output -match 'ERROR:') {
            Add-Summary 'FAIL' 'Lookup pipeline raised an exception (see 09-lookup.txt).'
        } else {
            Add-Summary 'WARN' 'Lookup pipeline returned no match for the known-good UPC (rate-limited?).'
        }
    } else {
        'lookup.py / _dx_lookup_check.py not reachable from working directory; skipped.' |
            Set-Content (Join-Path $reportDir '09-lookup.txt')
        Add-Summary 'WARN' 'Lookup pipeline test skipped (run from project folder).'
    }
}

Finalize-Report -ReportDir $reportDir -Project 'MediaInventory' -Sanitize:$Sanitize
