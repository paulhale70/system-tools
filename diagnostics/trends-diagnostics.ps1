<#
.SYNOPSIS
    View trends across past diagnostic runs.

.DESCRIPTION
    Reads the history file ($env:USERPROFILE\diagnostics-history.json)
    written by system-diagnostics.ps1 / app-diagnostics.ps1 and prints
    a summary of recorded runs, plus the top recurring WARN/FAIL
    verdicts. Optionally filter by project and/or host.

    Run from anywhere:
        powershell -ExecutionPolicy Bypass -File .\trends-diagnostics.ps1

.PARAMETER Project
    Filter to a specific project name (e.g. 'MediaInventory').

.PARAMETER ComputerName
    Filter to a specific host (default: all hosts).

.PARAMETER Top
    How many recurring verdicts to show. Default: 15.

.PARAMETER HistoryPath
    Override the path to the history file.
#>

[CmdletBinding()]
param(
    [string]$Project,
    [string]$ComputerName,
    [int]$Top = 15,
    [string]$HistoryPath = (Join-Path $env:USERPROFILE 'diagnostics-history.json')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $HistoryPath)) {
    Write-Host "No diagnostics history found at $HistoryPath." -ForegroundColor Yellow
    Write-Host "Run system-diagnostics.ps1 (or app-diagnostics.ps1) at least once and try again."
    return
}

$raw = Get-Content $HistoryPath -Raw
$history = @($raw | ConvertFrom-Json)

if ($Project)      { $history = @($history | Where-Object { $_.project -eq $Project }) }
if ($ComputerName) { $history = @($history | Where-Object { $_.host    -eq $ComputerName }) }

if ($history.Count -eq 0) {
    Write-Host "No runs match the filters." -ForegroundColor Yellow
    return
}

Write-Host ''
Write-Host '  Diagnostics history' -ForegroundColor Cyan
Write-Host ('  ' + ('-' * 60))
Write-Host ("  History file : $HistoryPath")
Write-Host ("  Total runs   : $($history.Count)")
Write-Host ("  Date range   : $($history[0].ts)  ->  $($history[-1].ts)")
if ($Project)      { Write-Host ("  Project      : $Project") }
if ($ComputerName) { Write-Host ("  Host         : $ComputerName") }
Write-Host ''

# Per project / host breakdown.
$byProject = $history | Group-Object project | Sort-Object Count -Descending
$byHost    = $history | Group-Object host    | Sort-Object Count -Descending

Write-Host 'Runs by project:'
foreach ($g in $byProject) { Write-Host ("  {0,-25} {1,5}" -f $g.Name, $g.Count) }
Write-Host ''
Write-Host 'Runs by host:'
foreach ($g in $byHost) { Write-Host ("  {0,-25} {1,5}" -f $g.Name, $g.Count) }

# Recurring WARN/FAIL across all selected runs.
Write-Host ''
Write-Host ("Top $Top recurring WARN/FAIL verdicts:") -ForegroundColor Cyan
$tally = @{}
foreach ($run in $history) {
    foreach ($v in $run.verdicts) {
        if ($v -match '^\[(WARN|FAIL)\]') {
            if (-not $tally.ContainsKey($v)) { $tally[$v] = 0 }
            $tally[$v] += 1
        }
    }
}
$ranked = $tally.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First $Top
foreach ($e in $ranked) {
    Write-Host ("  {0,4}x  {1}" -f $e.Value, $e.Key)
}

# Per-run summary table.
Write-Host ''
Write-Host 'Last 10 runs:' -ForegroundColor Cyan
$last = $history | Select-Object -Last 10
$rows = $last | ForEach-Object {
    [PSCustomObject]@{
        Date    = ([DateTime]::Parse($_.ts)).ToString('yyyy-MM-dd HH:mm')
        Host    = $_.host
        Project = $_.project
        OK      = [int]$_.counts.OK
        WARN    = [int]$_.counts.WARN
        FAIL    = [int]$_.counts.FAIL
    }
}
$rows | Format-Table -AutoSize | Out-String | Write-Host
