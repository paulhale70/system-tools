<#
.SYNOPSIS
    Analyze a crash dump (.dmp) and explain it in plain English.

.DESCRIPTION
    Works on any Windows crash dump:
      - blue screens       C:\Windows\Minidump\*.dmp, C:\Windows\MEMORY.DMP
      - recovered hangs    C:\Windows\LiveKernelReports\**\*.dmp
      - app crashes        %LOCALAPPDATA%\CrashDumps\*.dmp, WER .mdmp/.hdmp
      - any .dmp someone sends you

    Runs the Windows debugger (cdb.exe; WinDbg from the Microsoft Store
    works) with Microsoft's public symbols, then writes a report folder
    with an HTML page (what crashed, where, what to do, top of the stack,
    full debugger output) and a text version, and opens the HTML.

    Uses the same debugger search, symbol cache and plain-English rules
    as the crash-dump section of system-diagnostics.ps1, which must be in
    the same folder.

.PARAMETER Path
    One or more dump files. Leave it out to pick from the dumps found on
    this PC.

.PARAMETER List
    List the crash dumps found on this PC and stop.

.PARAMETER Days
    How far back -List and the picker look. Default: 90.

.PARAMETER ReportRoot
    Folder the report folder goes in. Default: SYSTEMTOOLS_REPORTS_DIR,
    otherwise the Desktop.

.PARAMETER SymbolCache
    Where downloaded symbols are cached. Default: %TEMP%\SymbolCache.

.PARAMETER JsonOut
    Also write the results as JSON to this file (used by the desktop app).
    With -List, writes the dump list instead.

.PARAMETER NoOpen
    Don't open the HTML report when done.

.EXAMPLE
    .\analyze-dump.ps1 -List

.EXAMPLE
    .\analyze-dump.ps1 C:\Windows\Minidump\111125-12687-01.dmp

.EXAMPLE
    .\analyze-dump.ps1
    Lists recent dumps and asks which ones to analyze.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)][string[]]$Path,
    [switch]$List,
    [int]$Days = 90,
    [string]$ReportRoot,
    [string]$SymbolCache = (Join-Path $env:TEMP 'SymbolCache'),
    [string]$JsonOut,
    [switch]$NoOpen
)

# Shared helpers: Get-CrashDumpFiles, Find-Cdb, Invoke-DumpAnalysis,
# New-ReportFolder, Test-Elevated. Dot-sourcing doesn't run its collector.
$lib = Join-Path $PSScriptRoot 'system-diagnostics.ps1'
if (-not (Test-Path $lib)) {
    Write-Host "system-diagnostics.ps1 must be next to this script ($PSScriptRoot)." -ForegroundColor Red
    exit 1
}
. $lib

function Save-Json($obj) {
    if (-not $JsonOut) { return }
    ConvertTo-Json -InputObject $obj -Depth 6 | Set-Content -Path $JsonOut -Encoding UTF8
}

function ConvertTo-DumpRow($d) {
    [PSCustomObject]@{
        kind = $d.Kind; name = $d.Name; path = $d.Path; sizeMB = $d.SizeMB
        written = $d.Written.ToString('yyyy-MM-dd HH:mm')
    }
}

$elevated = Test-Elevated
$dumps = @(Get-CrashDumpFiles -Days $Days -IncludeKernelDump)
$hiddenNote = if (-not $elevated) {
    'Not running as administrator, so blue-screen and hang dumps (C:\Windows\Minidump, LiveKernelReports, MEMORY.DMP) may be missing or unreadable.'
}

# --- List -------------------------------------------------------------------
if ($List) {
    Save-Json ([PSCustomObject]@{ elevated = $elevated; note = $hiddenNote; dumps = @($dumps | ForEach-Object { ConvertTo-DumpRow $_ }) })
    if ($dumps.Count -eq 0) {
        Write-Host "No crash dumps from the last $Days days."
    } else {
        $dumps | Format-Table @{n='Written';e={ $_.Written.ToString('yyyy-MM-dd HH:mm') }}, Kind, SizeMB, Path -AutoSize |
            Out-String -Width 400 | Write-Host
    }
    if ($hiddenNote) { Write-Host $hiddenNote -ForegroundColor Yellow }
    return
}

# --- Pick -------------------------------------------------------------------
if (-not $Path) {
    if ($dumps.Count -eq 0) {
        Write-Host "No crash dumps from the last $Days days. Pass a file: .\analyze-dump.ps1 <path-to.dmp>"
        if ($hiddenNote) { Write-Host $hiddenNote -ForegroundColor Yellow }
        return
    }
    Write-Host ''
    for ($i = 0; $i -lt $dumps.Count; $i++) {
        $d = $dumps[$i]
        Write-Host ('  {0,3}. {1}  {2,-18} {3,8} MB  {4}' -f ($i + 1), $d.Written.ToString('yyyy-MM-dd HH:mm'), $d.Kind, $d.SizeMB, $d.Name)
    }
    if ($hiddenNote) { Write-Host ''; Write-Host $hiddenNote -ForegroundColor Yellow }
    Write-Host ''
    $pick = Read-Host 'Number(s) to analyze, e.g. 1 or 1,3 (Enter for 1)'
    if (-not $pick) { $pick = '1' }
    $Path = @($pick -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } |
        ForEach-Object { [int]$_ - 1 } | Where-Object { $_ -ge 0 -and $_ -lt $dumps.Count } |
        ForEach-Object { $dumps[$_].Path })
    if (-not $Path) { Write-Host 'Nothing picked.'; return }
}

# --- Analyze ----------------------------------------------------------------
# powershell.exe -File passes "a.dmp,b.dmp" as one string; split it unless
# it really is one file.
$Path = @($Path | ForEach-Object {
    if ($_ -like '*,*' -and -not (Test-Path -LiteralPath $_)) { $_ -split ',' | Where-Object { $_ } } else { $_ }
})
$cdb = Find-Cdb
if (-not $cdb) {
    Write-Host $script:CDB_MISSING_HELP -ForegroundColor Yellow
    Save-Json ([PSCustomObject]@{ error = 'Windows Debugger (cdb.exe) not found. Install it with: winget install Microsoft.WinDbg' })
    exit 2
}

$folder = New-ReportFolder -Root $ReportRoot -Name ('DumpAnalysis-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$dir = $folder.Dir

$results = @(foreach ($p in $Path) {
    $known = $dumps | Where-Object { $_.Path -eq $p } | Select-Object -First 1
    $size = if (Test-Path -LiteralPath $p) { (Get-Item -LiteralPath $p).Length / 1MB } else { 0 }
    $slow = if ($size -gt 1024) { ' This is a large dump; it can take a long time.' } else { '' }
    Write-Host "Analyzing $(Split-Path $p -Leaf). The first analysis downloads symbols and can take a few minutes.$slow"
    Invoke-DumpAnalysis -Path $p -Cdb $cdb -SymbolCache $SymbolCache -Kind $(if ($known) { $known.Kind })
})

# Text: summary plus each dump's full debugger output.
$text = New-Object System.Text.StringBuilder
$null = $text.AppendLine("Crash dump analysis - $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
$null = $text.AppendLine("Debugger: $cdb")
$null = $text.AppendLine('')
foreach ($r in $results) {
    $null = $text.AppendLine('=' * 78)
    $null = $text.AppendLine("Dump     : $($r.Path)")
    $null = $text.AppendLine("Kind     : $($r.Kind)    Size: $($r.SizeMB) MB    Written: $($r.Written)")
    $null = $text.AppendLine("Summary  : $($r.Headline)")
    if ($r.Hint)          { $null = $text.AppendLine("Advice   : $($r.Hint)") }
    if ($r.ModuleInfo)    { $null = $text.AppendLine("Module   : $($r.ModuleInfo)") }
    if ($r.ExceptionText) { $null = $text.AppendLine("Exception: $($r.ExceptionText)") }
    if ($r.Stack)         { $null = $text.AppendLine('Stack    :'); $r.Stack | ForEach-Object { $null = $text.AppendLine("    $_") } }
    $null = $text.AppendLine('=' * 78)
    $null = $text.AppendLine($(if ($r.Error) { "ERROR: $($r.Error)" } else { $r.Output }))
}
$txtPath = Join-Path $dir 'dump-analysis.txt'
$text.ToString() | Set-Content -Path $txtPath -Encoding UTF8

# HTML.
function ConvertTo-HtmlText($s) { [System.Net.WebUtility]::HtmlEncode([string]$s) }
$cards = foreach ($r in $results) {
    $sev = if ($r.Error) { 'warn' } else { $r.Severity.ToLower() }
    $rows = [ordered]@{
        'Kind'      = $r.Kind
        'File'      = $r.Path
        'Size'      = $(if ($null -ne $r.SizeMB) { "$($r.SizeMB) MB" })
        'Written'   = $r.Written
        'Process'   = $r.Process
        'Bug-check' = $(if ($r.BugCheck) { "0x$($r.BugCheck) $($r.BugCheckName)" })
        'Exception' = $(if ($r.ExceptionCode) { "0x$($r.ExceptionCode)" + $(if ($r.ExceptionText) { " - $($r.ExceptionText)" }) } elseif ($r.ExceptionText) { $r.ExceptionText })
        'Module'    = (@($r.Image, $r.Module) | Where-Object { $_ } | Select-Object -Unique) -join ' / '
        'Made by'   = $r.ModuleInfo
        'Function'  = $r.Symbol
        'Bucket'    = $r.Bucket
    }
    $trs = ($rows.GetEnumerator() | Where-Object { $_.Value } |
        ForEach-Object { "<tr><th>$(ConvertTo-HtmlText $_.Key)</th><td>$(ConvertTo-HtmlText $_.Value)</td></tr>" }) -join "`n"
    $stack = if ($r.Stack) { "<h3>Top of the stack</h3><pre>$(ConvertTo-HtmlText ($r.Stack -join "`n"))</pre>" } else { '' }
    $raw = if ($r.Error) { '' } else { "<details><summary>Full debugger output</summary><pre>$(ConvertTo-HtmlText $r.Output)</pre></details>" }
    $hint = if ($r.Hint) { "<p class=""hint"">$(ConvertTo-HtmlText $r.Hint)</p>" } else { '' }
    @"
<section class="card $sev">
  <h2>$(ConvertTo-HtmlText $r.Headline)</h2>
  $hint
  <table>$trs</table>
  $stack
  $raw
</section>
"@
}
$note = if ($folder.Note) { "<p class=""note"">$(ConvertTo-HtmlText $folder.Note)</p>" } else { '' }
$html = @"
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Crash dump analysis</title>
<style>
:root { --bg:#fff; --panel:#f9fafb; --border:#e5e7eb; --text:#111827; --muted:#6b7280; --fail:#b91c1c; --warn:#b45309; --ok:#15803d; }
@media (prefers-color-scheme: dark) { :root { --bg:#111827; --panel:#1f2937; --border:#374151; --text:#f3f4f6; --muted:#9ca3af; --fail:#f87171; --warn:#fbbf24; --ok:#4ade80; } }
body { margin:0; padding:24px 16px; background:var(--bg); color:var(--text); font:14px/1.5 "Segoe UI", system-ui, sans-serif; }
main { max-width:980px; margin:0 auto; }
h1 { font-size:20px; margin:0 0 4px; } .sub { color:var(--muted); margin:0 0 20px; }
.card { background:var(--panel); border:1px solid var(--border); border-left:4px solid var(--warn); border-radius:8px; padding:16px 18px; margin:0 0 16px; }
.card.fail { border-left-color:var(--fail); } .card.ok { border-left-color:var(--ok); }
h2 { font-size:16px; margin:0 0 8px; } h3 { font-size:13px; margin:14px 0 6px; color:var(--muted); text-transform:uppercase; letter-spacing:.04em; }
.hint { margin:0 0 12px; } .note { color:var(--warn); }
table { border-collapse:collapse; width:100%; } th { text-align:left; color:var(--muted); font-weight:600; width:110px; vertical-align:top; padding:3px 12px 3px 0; }
td { padding:3px 0; word-break:break-all; }
pre { background:var(--bg); border:1px solid var(--border); border-radius:6px; padding:10px; overflow:auto; font:12px/1.45 Consolas, ui-monospace, monospace; max-height:520px; }
summary { cursor:pointer; color:var(--muted); margin-top:12px; }
</style></head>
<body><main>
<h1>Crash dump analysis</h1>
<p class="sub">$(ConvertTo-HtmlText (Get-Date -Format 'yyyy-MM-dd HH:mm')) &middot; $(ConvertTo-HtmlText $env:COMPUTERNAME) &middot; debugger $(ConvertTo-HtmlText (Split-Path $cdb -Leaf)) with Microsoft public symbols</p>
$note
$($cards -join "`n")
</main></body></html>
"@
$htmlPath = Join-Path $dir 'dump-analysis.html'
$html | Set-Content -Path $htmlPath -Encoding UTF8

Save-Json ([PSCustomObject]@{
    reportDir = $dir; html = $htmlPath; text = $txtPath; note = $folder.Note
    results = @($results | Select-Object * -ExcludeProperty Output)
})

Write-Host ''
foreach ($r in $results) {
    $color = if ($r.Severity -eq 'FAIL') { 'Red' } else { 'Yellow' }
    Write-Host "[$($r.Severity)] $($r.Name): $($r.Headline)" -ForegroundColor $color
    if ($r.Hint) { Write-Host "       $($r.Hint)" }
}
Write-Host ''
Write-Host "Report: $htmlPath" -ForegroundColor Green
if (-not $NoOpen -and -not $JsonOut) { Start-Process $htmlPath }
