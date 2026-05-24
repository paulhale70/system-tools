<#
.SYNOPSIS
    Compare two diagnostic reports and show what changed.

.DESCRIPTION
    Takes two report folders (or zips) produced by system-diagnostics.ps1
    or app-diagnostics.ps1 and produces a plain-text diff covering:
      - Summary verdicts (added / removed)
      - Hotfixes (added / removed)
      - Drivers (added / removed / version changed)
      - Services (state changes, added / removed)
      - Startup items
      - Event log counts per provider
      - Disk free space delta

    Useful for "did the fix actually change anything?" and "what's
    different vs. last week?".

.PARAMETER Old
    Path to the older report folder or zip.

.PARAMETER New
    Path to the newer report folder or zip.

.PARAMETER OutFile
    Path to write the diff report. Default: <New folder>\diff-vs-<old>.txt.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Old,
    [Parameter(Mandatory)][string]$New,
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'

function Resolve-ReportDir($path) {
    if (-not (Test-Path $path)) {
        throw "Not found: $path"
    }
    $item = Get-Item $path
    if ($item.PSIsContainer) { return $item.FullName }
    if ($item.Extension -ne '.zip') {
        throw "Expected a folder or .zip: $path"
    }
    $dest = Join-Path $env:TEMP ("diff-" + [guid]::NewGuid().ToString('N'))
    Expand-Archive -Path $item.FullName -DestinationPath $dest -Force
    return $dest
}

function Read-CsvSafe($path) {
    if (Test-Path $path) {
        try { return @(Import-Csv $path) } catch { return @() }
    }
    return @()
}

function Read-LinesSafe($path) {
    if (Test-Path $path) {
        try { return @(Get-Content $path) } catch { return @() }
    }
    return @()
}

$oldDir = Resolve-ReportDir $Old
$newDir = Resolve-ReportDir $New

$out = New-Object System.Text.StringBuilder
$null = $out.AppendLine("Diagnostics diff")
$null = $out.AppendLine("Old: $Old")
$null = $out.AppendLine("New: $New")
$null = $out.AppendLine(('=' * 70))

# --- Summary verdicts -------------------------------------------------------
$oldSummary = Read-LinesSafe (Join-Path $oldDir '00-SUMMARY.txt') | Where-Object { $_ -match '^\[' }
$newSummary = Read-LinesSafe (Join-Path $newDir '00-SUMMARY.txt') | Where-Object { $_ -match '^\[' }
$addedVerdicts   = $newSummary | Where-Object { $oldSummary -notcontains $_ }
$removedVerdicts = $oldSummary | Where-Object { $newSummary -notcontains $_ }

$null = $out.AppendLine('')
$null = $out.AppendLine('--- Summary verdicts ---')
if ($addedVerdicts) {
    $null = $out.AppendLine("Added ($($addedVerdicts.Count)):")
    foreach ($v in $addedVerdicts) { $null = $out.AppendLine("  + $v") }
}
if ($removedVerdicts) {
    $null = $out.AppendLine("Removed ($($removedVerdicts.Count)):")
    foreach ($v in $removedVerdicts) { $null = $out.AppendLine("  - $v") }
}
if (-not $addedVerdicts -and -not $removedVerdicts) {
    $null = $out.AppendLine('No changes.')
}

# --- Hotfixes ---------------------------------------------------------------
$oldHf = Read-CsvSafe (Join-Path $oldDir '04-hotfixes.csv') | ForEach-Object { $_.HotFixID }
$newHf = Read-CsvSafe (Join-Path $newDir '04-hotfixes.csv') | ForEach-Object { $_.HotFixID }
$addedHf   = $newHf | Where-Object { $oldHf -notcontains $_ }
$removedHf = $oldHf | Where-Object { $newHf -notcontains $_ }

$null = $out.AppendLine('')
$null = $out.AppendLine('--- Hotfixes ---')
if ($addedHf)   { $a = $addedHf -join ', ';   $null = $out.AppendLine("Added:   $a") }
if ($removedHf) { $r = $removedHf -join ', '; $null = $out.AppendLine("Removed: $r") }
if (-not $addedHf -and -not $removedHf) { $null = $out.AppendLine('No changes.') }

# --- Drivers ----------------------------------------------------------------
$oldDrv = Read-CsvSafe (Join-Path $oldDir '07-drivers.csv')
$newDrv = Read-CsvSafe (Join-Path $newDir '07-drivers.csv')
$oldMap = @{}; foreach ($d in $oldDrv) { $oldMap[$d.DeviceName] = $d.DriverVersion }
$newMap = @{}; foreach ($d in $newDrv) { $newMap[$d.DeviceName] = $d.DriverVersion }
$addedDrv   = $newMap.Keys | Where-Object { -not $oldMap.ContainsKey($_) }
$removedDrv = $oldMap.Keys | Where-Object { -not $newMap.ContainsKey($_) }
$changedDrv = $newMap.Keys | Where-Object { $oldMap.ContainsKey($_) -and $oldMap[$_] -ne $newMap[$_] }

$null = $out.AppendLine('')
$null = $out.AppendLine('--- Drivers ---')
if ($addedDrv) {
    $null = $out.AppendLine("Added ($($addedDrv.Count)):")
    foreach ($d in $addedDrv) { $null = $out.AppendLine("  + $d ($($newMap[$d]))") }
}
if ($removedDrv) {
    $null = $out.AppendLine("Removed ($($removedDrv.Count)):")
    foreach ($d in $removedDrv) { $null = $out.AppendLine("  - $d") }
}
if ($changedDrv) {
    $null = $out.AppendLine("Version changed ($($changedDrv.Count)):")
    foreach ($d in $changedDrv) { $null = $out.AppendLine("  ~ $d : $($oldMap[$d]) -> $($newMap[$d])") }
}
if (-not $addedDrv -and -not $removedDrv -and -not $changedDrv) {
    $null = $out.AppendLine('No changes.')
}

# --- Services ---------------------------------------------------------------
$oldSvc = Read-CsvSafe (Join-Path $oldDir '08-services.csv')
$newSvc = Read-CsvSafe (Join-Path $newDir '08-services.csv')
$oldSvcMap = @{}; foreach ($s in $oldSvc) { $oldSvcMap[$s.Name] = "$($s.Status)/$($s.StartType)" }
$newSvcMap = @{}; foreach ($s in $newSvc) { $newSvcMap[$s.Name] = "$($s.Status)/$($s.StartType)" }
$addedSvc   = $newSvcMap.Keys | Where-Object { -not $oldSvcMap.ContainsKey($_) }
$removedSvc = $oldSvcMap.Keys | Where-Object { -not $newSvcMap.ContainsKey($_) }
$changedSvc = $newSvcMap.Keys | Where-Object { $oldSvcMap.ContainsKey($_) -and $oldSvcMap[$_] -ne $newSvcMap[$_] }

$null = $out.AppendLine('')
$null = $out.AppendLine('--- Services ---')
if ($addedSvc)   { $a = $addedSvc -join ', ';   $null = $out.AppendLine("Added:   $a") }
if ($removedSvc) { $r = $removedSvc -join ', '; $null = $out.AppendLine("Removed: $r") }
if ($changedSvc) {
    $null = $out.AppendLine("State/StartType changed ($($changedSvc.Count)):")
    foreach ($s in $changedSvc) { $null = $out.AppendLine("  ~ $s : $($oldSvcMap[$s]) -> $($newSvcMap[$s])") }
}
if (-not $addedSvc -and -not $removedSvc -and -not $changedSvc) {
    $null = $out.AppendLine('No changes.')
}

# --- Startup items ----------------------------------------------------------
$oldSu = (Read-CsvSafe (Join-Path $oldDir '08-startup.csv')) | ForEach-Object { "$($_.Name) | $($_.Command)" }
$newSu = (Read-CsvSafe (Join-Path $newDir '08-startup.csv')) | ForEach-Object { "$($_.Name) | $($_.Command)" }
$addedSu   = $newSu | Where-Object { $oldSu -notcontains $_ }
$removedSu = $oldSu | Where-Object { $newSu -notcontains $_ }
$null = $out.AppendLine('')
$null = $out.AppendLine('--- Startup items ---')
if ($addedSu)   { foreach ($s in $addedSu)   { $null = $out.AppendLine("  + $s") } }
if ($removedSu) { foreach ($s in $removedSu) { $null = $out.AppendLine("  - $s") } }
if (-not $addedSu -and -not $removedSu) { $null = $out.AppendLine('No changes.') }

# --- Event log counts -------------------------------------------------------
$null = $out.AppendLine('')
$null = $out.AppendLine('--- Event log counts (System, Application) ---')
foreach ($log in 'System','Application') {
    $oldCount = (Read-CsvSafe (Join-Path $oldDir "05-events-$log.csv")).Count
    $newCount = (Read-CsvSafe (Join-Path $newDir "05-events-$log.csv")).Count
    $delta = $newCount - $oldCount
    $sign = if ($delta -gt 0) { '+' } elseif ($delta -lt 0) { '' } else { ' ' }
    $null = $out.AppendLine(("  {0,-12} {1,6} -> {2,6}  ({3}{4})" -f $log, $oldCount, $newCount, $sign, $delta))
}

# --- Disk space -------------------------------------------------------------
$oldDisks = Read-LinesSafe (Join-Path $oldDir '01-disks.txt') -join "`n"
$newDisks = Read-LinesSafe (Join-Path $newDir '01-disks.txt') -join "`n"
if ($oldDisks -and $newDisks -and $oldDisks -ne $newDisks) {
    $null = $out.AppendLine('')
    $null = $out.AppendLine('--- Disks ---')
    $null = $out.AppendLine('(see 01-disks.txt in each report for raw values; they differ)')
}

# --- Output -----------------------------------------------------------------
if (-not $OutFile) {
    $OutFile = Join-Path $newDir ("diff-vs-" + (Split-Path $oldDir -Leaf) + '.txt')
}
$out.ToString() | Set-Content -Path $OutFile -Encoding UTF8
Write-Host ''
Write-Host "Diff written to: $OutFile" -ForegroundColor Green
Write-Host ''
$out.ToString() | Write-Host
