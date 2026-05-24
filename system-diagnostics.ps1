<#
.SYNOPSIS
    Generic Windows diagnostic collector. Project-agnostic.

.DESCRIPTION
    Comprehensive Windows diagnostics in one script: system info,
    Python state, project files + git, installed updates, event logs
    (incl. bug-checks and app crashes), Reliability Monitor records,
    WER + LiveKernelReports + Minidumps + MEMORY.DMP, drivers, storage
    + SMART, memory modules, processes + services, startup items,
    scheduled-task failures, network state (adapters, TCP, DNS client,
    optional HTTP probes, proxy, time skew, firewall), DISM
    CheckHealth (admin), systeminfo, and HID devices. Writes a
    top-level SUMMARY.txt with green/yellow/red verdicts, then zips
    the bundle for sharing.

    Run from a project folder:
        powershell -ExecutionPolicy Bypass -File .\system-diagnostics.ps1

    Library mode (no auto-run):
        . .\system-diagnostics.ps1
        $dir = Initialize-Report -ProjectName 'MyApp'
        Invoke-SystemDiagnostics -ReportDir $dir -Endpoints @('https://example.com')
        Finalize-Report -ReportDir $dir

.PARAMETER OutputRoot
    Directory where the report folder and zip are written. Default: Desktop.

.PARAMETER EventLogDays
    Days of Application/System event log entries to collect. Default: 7.

.PARAMETER ProjectName
    Used as the report folder prefix. Default: 'System'.

.PARAMETER Endpoints
    Optional list of HTTP URLs to probe for reachability.

.PARAMETER WerKeywords
    Regex to filter Report.wer files by. Default: 'python|pythonw'.

.PARAMETER IncludeMiniDumps
    Copy C:\Windows\Minidump\*.dmp into the bundle (can be large).
    Without this flag only a listing is captured.

.PARAMETER CaptureNetSeconds
    Run 'netsh trace' for the given number of seconds and bundle the
    resulting .etl. Off when 0 (default). Requires elevation.

.PARAMETER Sanitize
    Redact obvious PII (username, computer name, MAC addresses, private
    IPs, user profile path) from all text files before zipping. Useful
    when sharing the report outside your team.

.PARAMETER ReportDir
    Reuse an existing report folder instead of creating a new one.

.PARAMETER NoFinalize
    Skip writing SUMMARY.txt and zipping. Useful when chaining with an
    app-specific diagnostic script.
#>

[CmdletBinding()]
param(
    [string]$OutputRoot        = [Environment]::GetFolderPath('Desktop'),
    [int]$EventLogDays         = 7,
    [string]$ProjectName       = 'System',
    [string[]]$Endpoints       = @(),
    [string]$WerKeywords       = 'python|pythonw',
    [switch]$IncludeMiniDumps,
    [int]$CaptureNetSeconds    = 0,
    [switch]$Sanitize,
    [string]$ReportDir,
    [switch]$NoFinalize
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Section($title) {
    Write-Host ''
    Write-Host ('=' * 70)
    Write-Host $title
    Write-Host ('=' * 70)
}

function Save-Text($name, $content) {
    $path = Join-Path $script:reportDir $name
    $content | Out-File -FilePath $path -Encoding UTF8
}

function Add-Summary($level, $msg) {
    $color = switch ($level) {
        'OK'   { 'Green' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
        default { 'White' }
    }
    $line = "[$level] $msg"
    Write-Host $line -ForegroundColor $color
    [void]$script:summary.Add($line)
}

function Try-Run($label, [scriptblock]$block) {
    try {
        & $block
    } catch {
        Write-Warning "$label failed: $($_.Exception.Message)"
        Add-Summary 'FAIL' "$label : $($_.Exception.Message)"
    }
}

function Test-Elevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Find-ProjectRoot {
    if ($PSScriptRoot) {
        $dir = $PSScriptRoot
    } else {
        $dir = (Get-Location).Path
    }
    while ($dir) {
        if (Test-Path (Join-Path $dir '.git')) { return $dir }
        $parent = Split-Path $dir -Parent
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    if ($PSScriptRoot) { return $PSScriptRoot }
    return (Get-Location).Path
}

function Invoke-PythonScript($projectRoot, $scriptPath) {
    try {
        Push-Location $projectRoot
        $out = & python $scriptPath 2>&1 | Out-String
        $exit = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    [PSCustomObject]@{ Output = $out; ExitCode = $exit }
}

function Get-LikelyFixes {
    param([string[]]$SummaryLines)
    # Each rule: regex matched against summary text -> plain-English fix.
    $rules = @(
        @{ Pattern = 'bug-check|BSOD|MEMORY\.DMP'                            ; Fix = 'Recent kernel crashes detected. Causes are usually a bad driver or failing RAM. Update graphics/storage drivers, then run Windows Memory Diagnostic (mdsched.exe).' }
        @{ Pattern = 'app crash|crash/hang'                                   ; Fix = 'One or more applications crashed recently. Reinstall the failing app and check for Windows + .NET updates.' }
        @{ Pattern = 'physical disk.*not healthy'                             ; Fix = 'A physical disk reports as unhealthy. Back up your data immediately and consider replacing the drive.' }
        @{ Pattern = 'Clock skew is'                                          ; Fix = 'System clock is out of sync. Fix it under Settings > Time and language > Date and time > Sync now.' }
        @{ Pattern = 'No real Python on PATH'                                 ; Fix = 'No working Python is installed. Get one from https://python.org (check Add to PATH during install).' }
        @{ Pattern = 'WindowsApps python\.exe stub'                           ; Fix = 'Disable the python.exe stub under Settings > Apps > Advanced app settings > App execution aliases.' }
        @{ Pattern = 'WinINET proxy is enabled'                               ; Fix = 'A proxy is intercepting web requests. If you do not need it, turn it off under Settings > Network and internet > Proxy.' }
        @{ Pattern = 'No endpoints reachable|DNS lookup failed'               ; Fix = 'Network requests are failing. Try a different network, or change DNS to 1.1.1.1 / 8.8.8.8 under your adapter settings.' }
        @{ Pattern = 'DB file is a cloud placeholder'                         ; Fix = 'Database file has not been downloaded by your cloud sync. Right-click it in File Explorer and choose Always keep on this device.' }
        @{ Pattern = 'DB integrity check returned errors'                     ; Fix = 'SQLite database is corrupt. Restore from your most recent backup.' }
        @{ Pattern = 'DISM reports component store issues'                    ; Fix = 'Windows component store has issues. Open elevated PowerShell and run: DISM /Online /Cleanup-Image /RestoreHealth then sfc /scannow.' }
        @{ Pattern = 'Not elevated'                                           ; Fix = 'Re-run elevated (right-click PowerShell > Run as administrator) to capture admin-only data like DISM and some event logs.' }
    )
    $fixes = New-Object System.Collections.ArrayList
    foreach ($rule in $rules) {
        if (($SummaryLines | Out-String) -match $rule.Pattern) {
            [void]$fixes.Add($rule.Fix)
        }
    }
    return $fixes
}

function Invoke-Sanitize {
    param([string]$Dir)
    # Build replacement map of obvious PII.
    $replacements = [ordered]@{
        ([Regex]::Escape($env:COMPUTERNAME))                                                     = '<PC>'
        ([Regex]::Escape($env:USERNAME))                                                         = '<USER>'
        ([Regex]::Escape($env:USERPROFILE))                                                      = '<USERPROFILE>'
        '\b([0-9A-Fa-f]{2}[-:]){5}[0-9A-Fa-f]{2}\b'                                              = '<MAC>'
        '\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'                                                      = '<10.x.x.x>'
        '\b192\.168\.\d{1,3}\.\d{1,3}\b'                                                         = '<192.168.x.x>'
        '\b172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}\b'                                          = '<172.16-31.x.x>'
    }
    if ($env:USERDOMAIN) { $replacements[[Regex]::Escape($env:USERDOMAIN)] = '<DOMAIN>' }

    Get-ChildItem -Path $Dir -Recurse -File -Include '*.txt','*.csv','*.log','*.html','*.json' -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                $content = Get-Content $_.FullName -Raw -ErrorAction Stop
                foreach ($pat in $replacements.Keys) {
                    $content = [Regex]::Replace($content, $pat, $replacements[$pat], 'IgnoreCase')
                }
                Set-Content -Path $_.FullName -Value $content -Encoding UTF8 -NoNewline
            } catch {}
        }
}

function Write-HtmlReport {
    param([string]$Dir, [string]$Title = 'Diagnostics Report', [string[]]$Fixes = @())

    $generated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

    $rows = foreach ($line in $script:summary) {
        $level = ($line -split ' ',2)[0] -replace '\[|\]',''
        $msg   = ($line -split ' ',2)[1]
        $cls = switch ($level) { 'OK' {'ok'} 'WARN' {'warn'} 'FAIL' {'fail'} default {'info'} }
        "<tr class='$cls'><td class='lvl'>$level</td><td>$([System.Web.HttpUtility]::HtmlEncode($msg))</td></tr>"
    }
    $rowsHtml = $rows -join ''
    $verdictTable = "<table class='verdicts'><thead><tr><th>Level</th><th>Finding</th></tr></thead><tbody>$rowsHtml</tbody></table>"

    $fixesHtml = if ($Fixes.Count -gt 0) {
        $items = ($Fixes | ForEach-Object { '<li>' + [System.Web.HttpUtility]::HtmlEncode($_) + '</li>' }) -join ''
        "<details open><summary><b>Likely fixes ($($Fixes.Count))</b></summary><ul class='fixes'>$items</ul></details>"
    } else {
        '<p class="muted">No likely-fix matches.</p>'
    }

    $fileLinks = Get-ChildItem -Path $Dir -File -ErrorAction SilentlyContinue |
        Sort-Object Name |
        Where-Object { $_.Name -notmatch '\.(html|zip)$' } |
        ForEach-Object {
            $name = $_.Name
            $size = if ($_.Length -gt 1KB) { "$([math]::Round($_.Length/1KB,1)) KB" } else { "$($_.Length) B" }
            "<li><a href='$name'>$name</a> <span class='muted'>$size</span></li>"
        }
    $fileCount = (Get-ChildItem $Dir -File).Count
    $fileLinksHtml = $fileLinks -join ''
    $fileList = "<details><summary><b>All collected files ($fileCount)</b></summary><ul>$fileLinksHtml</ul></details>"

    Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue

    $css = @'
body { font: 14px/1.5 -apple-system, Segoe UI, Helvetica, Arial, sans-serif; max-width: 1100px; margin: 24px auto; padding: 0 16px; color: #1a1a1a; }
h1 { margin: 0 0 4px; font-size: 22px; }
.subtitle { color: #666; margin-bottom: 24px; }
table { border-collapse: collapse; width: 100%; margin: 8px 0 16px; }
th, td { padding: 6px 10px; text-align: left; border-bottom: 1px solid #eee; vertical-align: top; }
th { background: #f4f4f6; font-size: 12px; text-transform: uppercase; letter-spacing: .04em; color: #555; }
td.lvl { font-weight: 600; width: 80px; }
tr.ok td.lvl   { color: #138a36; }
tr.warn td.lvl { color: #a06200; }
tr.fail td.lvl { color: #b3261e; }
ul.fixes li { margin-bottom: 6px; }
details { background: #fafafa; border: 1px solid #e5e5ea; border-radius: 6px; padding: 10px 14px; margin: 10px 0; }
details summary { cursor: pointer; outline: none; }
.muted { color: #888; font-size: 12px; }
'@

    $html = @"
<!DOCTYPE html>
<html><head><meta charset='utf-8'><title>$Title</title><style>$css</style></head>
<body>
<h1>$Title</h1>
<div class='subtitle'>Generated $generated on host $env:COMPUTERNAME (user $env:USERNAME).</div>
<h2>Likely fixes</h2>
$fixesHtml
<h2>Verdicts</h2>
$verdictTable
<h2>Files</h2>
$fileList
</body></html>
"@
    $html | Set-Content -Path (Join-Path $Dir '00-summary.html') -Encoding UTF8
}

function Initialize-Report {
    param(
        [string]$OutputRoot  = [Environment]::GetFolderPath('Desktop'),
        [string]$ProjectName = 'System'
    )
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dir = Join-Path $OutputRoot "$ProjectName-Diagnostics-$timestamp"
    $null = New-Item -ItemType Directory -Path $dir -Force

    $script:reportDir  = $dir
    $script:summary    = New-Object System.Collections.ArrayList
    $script:transcript = Join-Path $dir 'collector.log'
    Start-Transcript -Path $script:transcript -Append | Out-Null
    return $dir
}

function Finalize-Report {
    param(
        [string]$ReportDir = $script:reportDir,
        [switch]$Sanitize
    )

    $summaryPath = Join-Path $ReportDir '00-SUMMARY.txt'
    $generated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

    $likelyFixes = Get-LikelyFixes -SummaryLines $script:summary

    $header = @(
        "Diagnostics summary"
        "Generated: $generated"
        "Host: $env:COMPUTERNAME  User: $env:USERNAME"
        ('-' * 60)
        ''
    )
    $counts = $script:summary | Group-Object { ($_ -split ' ',2)[0] } |
        ForEach-Object { "{0,-7} {1}" -f $_.Name, $_.Count }

    $fixBlock = @()
    if ($likelyFixes.Count -gt 0) {
        $fixBlock += ''
        $fixBlock += 'Likely fixes:'
        for ($i = 0; $i -lt $likelyFixes.Count; $i++) {
            $fixBlock += ("  {0}. {1}" -f ($i + 1), $likelyFixes[$i])
        }
    }

    ($header + $counts + $fixBlock + '' + ($script:summary | Sort-Object)) -join "`r`n" |
        Set-Content $summaryPath -Encoding UTF8

    Write-HtmlReport -Dir $ReportDir -Title "Diagnostics: $env:COMPUTERNAME" -Fixes $likelyFixes

    Stop-Transcript | Out-Null

    if ($Sanitize) {
        Write-Host ''
        Write-Host 'Sanitizing report (redacting username, hostname, MACs, private IPs)...' -ForegroundColor Yellow
        Invoke-Sanitize -Dir $ReportDir
    }

    $zipPath = "$ReportDir.zip"
    Compress-Archive -Path (Join-Path $ReportDir '*') -DestinationPath $zipPath -Force -CompressionLevel Optimal

    Write-Host ''
    Write-Host 'Diagnostics collected:' -ForegroundColor Green
    Write-Host "  Folder: $ReportDir"
    $htmlReport = Join-Path $ReportDir '00-summary.html'
    Write-Host "  Report: $htmlReport"
    Write-Host "  Zip:    $zipPath"
    Write-Host ''
    Write-Host 'Top-level verdicts:'
    Get-Content $summaryPath | Select-Object -First 50 | ForEach-Object { Write-Host "  $_" }

    if (-not $env:CI) {
        Try-Run 'Open report' { Start-Process (Join-Path $ReportDir '00-summary.html') }
    }
}

# ---------------------------------------------------------------------------
# System diagnostic sections
# ---------------------------------------------------------------------------

function Invoke-SystemDiagnostics {
    param(
        [string]$ReportDir   = $script:reportDir,
        [int]$EventLogDays     = 7,
        [string[]]$Endpoints   = @(),
        [string]$WerKeywords   = 'python|pythonw',
        [switch]$IncludeMiniDumps,
        [int]$CaptureNetSeconds = 0
    )
    $script:reportDir = $ReportDir
    $since = (Get-Date).AddDays(-$EventLogDays)

    $isAdmin = Test-Elevated
    if ($isAdmin) {
        Add-Summary 'OK' 'Running elevated.'
    } else {
        Add-Summary 'WARN' 'Not elevated - DISM, some event-log providers, and some WMI classes may be incomplete.'
    }

    # -----------------------------------------------------------------------
    # 1. System information
    # -----------------------------------------------------------------------
    Write-Section '1. System information'
    Try-Run 'System info' {
        $os   = Get-CimInstance Win32_OperatingSystem
        $cs   = Get-CimInstance Win32_ComputerSystem
        $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
        $bios = Get-CimInstance Win32_BIOS

        $uptime = ((Get-Date) - $os.LastBootUpTime).ToString('d\.hh\:mm\:ss')
        $info = [PSCustomObject]@{
            Timestamp         = (Get-Date).ToString('o')
            ComputerName      = $env:COMPUTERNAME
            UserName          = "$env:USERDOMAIN\$env:USERNAME"
            Elevated          = $isAdmin
            OSCaption         = $os.Caption
            OSVersion         = $os.Version
            OSBuild           = $os.BuildNumber
            OSArchitecture    = $os.OSArchitecture
            InstallDate       = $os.InstallDate
            LastBootUpTime    = $os.LastBootUpTime
            Uptime            = $uptime
            Manufacturer      = $cs.Manufacturer
            Model             = $cs.Model
            TotalMemoryGB     = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
            FreeMemoryGB      = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
            CPU               = $cpu.Name
            CPUCores          = $cpu.NumberOfCores
            CPULogical        = $cpu.NumberOfLogicalProcessors
            CPUMaxClockMHz    = $cpu.MaxClockSpeed
            BIOSVersion       = $bios.SMBIOSBIOSVersion
            BIOSReleaseDate   = $bios.ReleaseDate
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            Culture           = (Get-Culture).Name
            TimeZone          = (Get-TimeZone).Id
        }
        $info | Format-List | Out-String | Set-Content (Join-Path $ReportDir '01-system-info.txt')

        Get-PSDrive -PSProvider FileSystem |
            Select-Object Name, @{n='UsedGB';e={[math]::Round($_.Used/1GB,2)}}, @{n='FreeGB';e={[math]::Round($_.Free/1GB,2)}}, Root |
            Format-Table -AutoSize | Out-String |
            Set-Content (Join-Path $ReportDir '01-disks.txt')
    }

    # -----------------------------------------------------------------------
    # 2. Python + dependencies
    # -----------------------------------------------------------------------
    Write-Section '2. Python + dependencies'
    Try-Run 'Python detection' {
        $pyOut = New-Object System.Text.StringBuilder
        $stubAhead = $false

        foreach ($cmd in 'python','py','python3') {
            $exe = Get-Command $cmd -ErrorAction SilentlyContinue
            if ($exe) {
                $null = $pyOut.AppendLine("--- $cmd ($($exe.Source)) ---")
                if ($exe.Source -match '\\WindowsApps\\') {
                    $null = $pyOut.AppendLine('(WindowsApps app-execution-alias stub - not a real Python.)')
                    if ($cmd -eq 'python') { $stubAhead = $true }
                    continue
                }
                $null = $pyOut.AppendLine((& $cmd --version 2>&1 | Out-String).Trim())
                $null = $pyOut.AppendLine((& $cmd -c "import sys; print(sys.executable); print(sys.version); print(sys.path)" 2>&1 | Out-String))
            }
        }

        $real = Get-Command python -All -ErrorAction SilentlyContinue |
            Where-Object { $_.Source -notmatch '\\WindowsApps\\' } | Select-Object -First 1
        if ($real) {
            Add-Summary 'OK' "python -> $($real.Source)"
        } else {
            Add-Summary 'FAIL' 'No real Python on PATH (only WindowsApps stub or none).'
        }
        if ($stubAhead -and $real) {
            Add-Summary 'WARN' 'WindowsApps python.exe stub is on PATH; disable it under Settings > Apps > App execution aliases.'
        }

        $pip = Get-Command pip -ErrorAction SilentlyContinue
        if ($pip) {
            $null = $pyOut.AppendLine('--- pip list ---')
            $null = $pyOut.AppendLine((& pip list 2>&1 | Out-String))
            $null = $pyOut.AppendLine('--- pip freeze ---')
            $null = $pyOut.AppendLine((& pip freeze 2>&1 | Out-String))
        }

        Save-Text '02-python.txt' $pyOut.ToString()
    }

    # -----------------------------------------------------------------------
    # 3. Project files + git state
    # -----------------------------------------------------------------------
    Write-Section '3. Project files'
    Try-Run 'Project inventory' {
        $projectRoot = Find-ProjectRoot

        $files = Get-ChildItem -Path $projectRoot -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.Length -lt 50MB }

        $files |
            Select-Object FullName, Length, LastWriteTime,
                @{n='SHA256';e={ (Get-FileHash $_.FullName -Algorithm SHA256).Hash }} |
            Format-Table -AutoSize | Out-String |
            Set-Content (Join-Path $ReportDir '03-project-files.txt')

        if (Test-Path (Join-Path $projectRoot 'requirements.txt')) {
            Copy-Item (Join-Path $projectRoot 'requirements.txt') (Join-Path $ReportDir '03-requirements.txt') -Force
        }

        if (Test-Path (Join-Path $projectRoot '.git')) {
            $gitOut = New-Object System.Text.StringBuilder
            Push-Location $projectRoot
            try {
                $null = $gitOut.AppendLine('--- git status ---')
                $null = $gitOut.AppendLine((& git status 2>&1 | Out-String))
                $null = $gitOut.AppendLine('--- git log -5 ---')
                $null = $gitOut.AppendLine((& git log --oneline -5 2>&1 | Out-String))
                $null = $gitOut.AppendLine('--- branch ---')
                $null = $gitOut.AppendLine((& git rev-parse --abbrev-ref HEAD 2>&1 | Out-String))
            } finally {
                Pop-Location
            }
            Save-Text '03-git.txt' $gitOut.ToString()
        }
    }

    # -----------------------------------------------------------------------
    # 4. Installed updates (hotfixes)
    # -----------------------------------------------------------------------
    Write-Section '4. Installed updates'
    Try-Run 'Hotfixes' {
        Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending |
            Select-Object HotFixID, Description, InstalledOn, InstalledBy |
            Export-Csv -NoTypeInformation -Path (Join-Path $ReportDir '04-hotfixes.csv')
    }

    # -----------------------------------------------------------------------
    # 5. Event logs + bug-checks + app crashes + reliability records
    # -----------------------------------------------------------------------
    Write-Section '5. Event logs + crashes'
    Try-Run 'Event log' {
        foreach ($log in 'Application','System','Setup') {
            $events = Get-WinEvent -FilterHashtable @{
                LogName   = $log
                Level     = 1,2,3
                StartTime = $since
            } -ErrorAction SilentlyContinue

            if ($events) {
                $events |
                    Select-Object TimeCreated, LevelDisplayName, ProviderName, Id,
                        @{n='Message';e={ ($_.Message -replace '\s+',' ').Substring(0, [Math]::Min(500, $_.Message.Length)) }} |
                    Sort-Object TimeCreated -Descending |
                    ConvertTo-Csv -NoTypeInformation |
                    Set-Content (Join-Path $ReportDir "05-events-$log.csv")
            } else {
                "No $log events in the last $EventLogDays days." |
                    Set-Content (Join-Path $ReportDir "05-events-$log.csv")
            }
        }
    }

    Try-Run 'Bug-checks / BSOD' {
        $bugchecks = Get-WinEvent -FilterHashtable @{
            LogName  = 'System'
            Id       = 41, 1001, 6008, 1003
        } -ErrorAction SilentlyContinue | Where-Object { $_.TimeCreated -ge $since } |
            Select-Object TimeCreated, Id, ProviderName, LevelDisplayName,
                @{n='Message';e={ ($_.Message -replace '\s+',' ').Substring(0, [Math]::Min(500, $_.Message.Length)) }}
        if ($bugchecks) {
            $bugchecks | Export-Csv -NoTypeInformation -Path (Join-Path $ReportDir '05-bugchecks.csv')
            Add-Summary 'WARN' ("$($bugchecks.Count) bug-check/power-loss events in the last $EventLogDays days.")
        } else {
            "No bug-check events in the last $EventLogDays days." |
                Set-Content (Join-Path $ReportDir '05-bugchecks.csv')
        }
    }

    Try-Run 'App crashes / hangs' {
        $appcrash = Get-WinEvent -FilterHashtable @{
            LogName      = 'Application'
            ProviderName = 'Application Error','Windows Error Reporting','Application Hang','.NET Runtime'
        } -ErrorAction SilentlyContinue | Where-Object { $_.TimeCreated -ge $since } |
            Select-Object TimeCreated, Id, ProviderName, LevelDisplayName,
                @{n='Message';e={ ($_.Message -replace '\s+',' ').Substring(0, [Math]::Min(500, $_.Message.Length)) }}
        if ($appcrash) {
            $appcrash | Export-Csv -NoTypeInformation -Path (Join-Path $ReportDir '05-app-crashes.csv')
            Add-Summary 'WARN' ("$($appcrash.Count) app crash/hang events in the last $EventLogDays days.")
        } else {
            "No app crash/hang events in the last $EventLogDays days." |
                Set-Content (Join-Path $ReportDir '05-app-crashes.csv')
        }
    }

    Try-Run 'Reliability records' {
        Get-CimInstance Win32_ReliabilityRecords -ErrorAction SilentlyContinue |
            Where-Object { $_.TimeGenerated -ge $since } |
            Select-Object TimeGenerated, SourceName, ProductName, EventIdentifier,
                @{n='Message';e={ ($_.Message -replace '\s+',' ') }} |
            Export-Csv -NoTypeInformation -Path (Join-Path $ReportDir '05-reliability.csv')
    }

    # -----------------------------------------------------------------------
    # 6. WER + LiveKernelReports + Minidumps + MEMORY.DMP
    # -----------------------------------------------------------------------
    Write-Section '6. Crash artifacts (WER, LKR, dumps)'
    Try-Run 'WER artifacts' {
        $werRoots = @(
            Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER\ReportArchive'
            Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER\ReportQueue'
            Join-Path $env:ProgramData  'Microsoft\Windows\WER\ReportArchive'
            Join-Path $env:ProgramData  'Microsoft\Windows\WER\ReportQueue'
        )
        $hits = foreach ($root in $werRoots) {
            if (Test-Path $root) {
                Get-ChildItem -Path $root -Recurse -Filter 'Report.wer' -ErrorAction SilentlyContinue |
                    Where-Object {
                        $txt = Get-Content $_.FullName -ErrorAction SilentlyContinue -Raw
                        $txt -match $WerKeywords
                    }
            }
        }
        if ($hits) {
            $werDir = Join-Path $ReportDir 'wer-reports'
            $null = New-Item -ItemType Directory -Path $werDir -Force
            foreach ($h in $hits) {
                $dest = Join-Path $werDir ($h.Directory.Name + '_' + $h.Name)
                Copy-Item $h.FullName $dest -Force
            }
            "Copied $($hits.Count) matching WER reports (filter: $WerKeywords)." |
                Set-Content (Join-Path $ReportDir '06-wer.txt')
        } else {
            "No WER reports matching filter '$WerKeywords' found." |
                Set-Content (Join-Path $ReportDir '06-wer.txt')
        }
    }

    Try-Run 'LiveKernelReports' {
        $lkr = 'C:\Windows\LiveKernelReports'
        if (Test-Path $lkr) {
            Get-ChildItem $lkr -Recurse -ErrorAction SilentlyContinue |
                Select-Object FullName, Length, LastWriteTime |
                Export-Csv -NoTypeInformation -Path (Join-Path $ReportDir '06-livekernelreports.csv')
        } else {
            'LiveKernelReports directory not present.' |
                Set-Content (Join-Path $ReportDir '06-livekernelreports.csv')
        }
    }

    Try-Run 'Minidumps + MEMORY.DMP' {
        $dumpDirs = @(
            Join-Path $env:LOCALAPPDATA 'CrashDumps'
            'C:\Windows\Minidump'
        )
        $dumps = foreach ($d in $dumpDirs) {
            if (Test-Path $d) {
                Get-ChildItem $d -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-30) }
            }
        }
        if ($dumps) {
            $dumps |
                Select-Object FullName, Length, LastWriteTime |
                Export-Csv -NoTypeInformation -Path (Join-Path $ReportDir '06-crash-dumps.csv')
            if ($IncludeMiniDumps) {
                $dest = Join-Path $ReportDir 'minidumps'
                $null = New-Item -ItemType Directory -Path $dest -Force
                $dumps | Copy-Item -Destination $dest -Force
                Add-Summary 'OK' "Copied $($dumps.Count) crash dumps into the bundle."
            } else {
                Add-Summary 'WARN' "$($dumps.Count) crash dumps found (pass -IncludeMiniDumps to copy them)."
            }
        } else {
            'No recent crash dumps found.' |
                Set-Content (Join-Path $ReportDir '06-crash-dumps.csv')
        }
        if (Test-Path 'C:\Windows\MEMORY.DMP') {
            $mem = Get-Item 'C:\Windows\MEMORY.DMP'
            "Path,SizeMB,LastWriteTime`r`n$($mem.FullName),$([math]::Round($mem.Length/1MB,1)),$($mem.LastWriteTime)" |
                Set-Content (Join-Path $ReportDir '06-memory-dmp.csv')
            Add-Summary 'WARN' ("C:\Windows\MEMORY.DMP present ({0:N1} MB) - indicates a recent kernel crash." -f ($mem.Length/1MB))
        }
    }

    Try-Run 'Crash dump auto-analysis' {
        # Try common cdb.exe / kd.exe locations from Windows Debugging Tools.
        $cdb = @(
            'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe'
            'C:\Program Files\Debugging Tools for Windows (x64)\cdb.exe'
            'C:\Program Files (x86)\Windows Kits\10\Debuggers\x86\cdb.exe'
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1

        $dumpsToAnalyze = @()
        $minidumpDir = 'C:\Windows\Minidump'
        if (Test-Path $minidumpDir) {
            $dumpsToAnalyze += Get-ChildItem $minidumpDir -File -Filter '*.dmp' -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-30) } |
                Sort-Object LastWriteTime -Descending | Select-Object -First 3
        }

        if (-not $cdb) {
            'cdb.exe not found. Install Windows Debugging Tools (part of the Windows SDK) to enable crash-dump analysis.' |
                Set-Content (Join-Path $ReportDir '06-dump-analysis.txt')
        } elseif ($dumpsToAnalyze.Count -eq 0) {
            'No recent .dmp files in C:\Windows\Minidump to analyze.' |
                Set-Content (Join-Path $ReportDir '06-dump-analysis.txt')
        } else {
            $out = New-Object System.Text.StringBuilder
            foreach ($d in $dumpsToAnalyze) {
                $null = $out.AppendLine("=== $($d.FullName) ($($d.LastWriteTime)) ===")
                $analysis = & $cdb -z $d.FullName -c '!analyze -v;q' -lines -logo NUL 2>&1 | Out-String
                $null = $out.AppendLine($analysis)
                $null = $out.AppendLine('')
            }
            Save-Text '06-dump-analysis.txt' $out.ToString()
            Add-Summary 'OK' "Analyzed $($dumpsToAnalyze.Count) recent crash dumps via cdb.exe."
        }
    }

    # -----------------------------------------------------------------------
    # 7. Hardware: drivers, storage, memory
    # -----------------------------------------------------------------------
    Write-Section '7. Hardware: drivers, storage, memory'
    Try-Run 'Drivers' {
        Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
            Select-Object DeviceName, Manufacturer, DriverVersion, DriverDate, IsSigned, InfName |
            Export-Csv -NoTypeInformation -Path (Join-Path $ReportDir '07-drivers.csv')
    }

    Try-Run 'Storage / SMART' {
        Get-PhysicalDisk -ErrorAction SilentlyContinue |
            Select-Object FriendlyName, MediaType, BusType,
                @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}},
                HealthStatus, OperationalStatus, SerialNumber |
            Export-Csv -NoTypeInformation -Path (Join-Path $ReportDir '07-physical-disks.csv')

        Get-Volume -ErrorAction SilentlyContinue |
            Select-Object DriveLetter, FileSystemLabel, FileSystem, HealthStatus,
                @{n='SizeRemainingGB';e={[math]::Round($_.SizeRemaining/1GB,1)}},
                @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}} |
            Export-Csv -NoTypeInformation -Path (Join-Path $ReportDir '07-volumes.csv')

        $unhealthy = Get-PhysicalDisk -ErrorAction SilentlyContinue |
            Where-Object { $_.HealthStatus -ne 'Healthy' -and $_.HealthStatus }
        if ($unhealthy) {
            Add-Summary 'FAIL' ("$($unhealthy.Count) physical disk(s) not healthy: " +
                (($unhealthy | ForEach-Object { "$($_.FriendlyName) [$($_.HealthStatus)]" }) -join '; '))
        }

        Get-StorageReliabilityCounter -PhysicalDisk (Get-PhysicalDisk -ErrorAction SilentlyContinue) -ErrorAction SilentlyContinue |
            Export-Csv -NoTypeInformation -Path (Join-Path $ReportDir '07-smart-reliability.csv')
    }

    Try-Run 'Memory modules' {
        Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue |
            Select-Object Manufacturer, PartNumber,
                @{n='CapacityGB';e={[math]::Round($_.Capacity/1GB,1)}},
                Speed, ConfiguredClockSpeed, DeviceLocator |
            Export-Csv -NoTypeInformation -Path (Join-Path $ReportDir '07-memory-modules.csv')
    }

    Try-Run 'Battery health' {
        $batt = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
        if (-not $batt) {
            'No battery present (desktop or VM).' |
                Set-Content (Join-Path $ReportDir '07-battery.txt')
            return
        }
        $report = Join-Path $ReportDir '07-battery-report.html'
        try {
            & powercfg /batteryreport /output $report /duration 14 2>&1 | Out-Null
            if (Test-Path $report) {
                # powercfg report includes design vs full-charge capacity.
                $html = Get-Content $report -Raw
                if ($html -match 'DESIGN CAPACITY[^<]*<[^>]*>([0-9,]+)\s*mWh' -and
                    $html -match 'FULL CHARGE CAPACITY[^<]*<[^>]*>([0-9,]+)\s*mWh') {
                    # Naive scrape; on most systems powercfg uses a table - this is best-effort.
                }
                Add-Summary 'OK' 'Battery report generated (07-battery-report.html).'
            }
        } catch {
            Add-Summary 'WARN' "Battery report failed: $($_.Exception.Message)"
        }
        $info = $batt | Select-Object Name, BatteryStatus, EstimatedChargeRemaining,
            EstimatedRunTime, DesignVoltage, DesignCapacity, FullChargeCapacity
        $info | Format-List | Out-String |
            Set-Content (Join-Path $ReportDir '07-battery.txt')
    }

    # -----------------------------------------------------------------------
    # 8. Processes + services + startup + scheduled tasks
    # -----------------------------------------------------------------------
    Write-Section '8. Processes, services, startup, tasks'
    Try-Run 'Processes' {
        Get-Process -ErrorAction SilentlyContinue | Sort-Object WS -Descending |
            Select-Object Id, ProcessName,
                @{n='WS_MB';e={[math]::Round($_.WS/1MB,1)}},
                @{n='CPU_s';e={[math]::Round($_.CPU,1)}},
                StartTime, Path -First 200 |
            Export-Csv -NoTypeInformation -Path (Join-Path $ReportDir '08-processes.csv')

        Get-Process -Name 'python','pythonw' -ErrorAction SilentlyContinue |
            Select-Object Id, ProcessName, StartTime,
                @{n='WorkingSetMB';e={[math]::Round($_.WorkingSet64/1MB,1)}},
                @{n='CPUSeconds';e={[math]::Round($_.CPU,1)}},
                Path |
            Format-Table -AutoSize | Out-String |
            Set-Content (Join-Path $ReportDir '08-python-processes.txt')
    }

    Try-Run 'Services' {
        Get-Service -ErrorAction SilentlyContinue |
            Select-Object Name, DisplayName, Status, StartType |
            Export-Csv -NoTypeInformation -Path (Join-Path $ReportDir '08-services.csv')
    }

    Try-Run 'Startup items' {
        Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue |
            Select-Object Name, Command, Location, User |
            Export-Csv -NoTypeInformation -Path (Join-Path $ReportDir '08-startup.csv')
    }

    Try-Run 'Scheduled task failures' {
        Get-ScheduledTask -ErrorAction SilentlyContinue | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue |
            Where-Object { $_.LastTaskResult -ne 0 -and $_.LastRunTime -ge $since } |
            Select-Object TaskName, TaskPath, LastRunTime, LastTaskResult, NumberOfMissedRuns |
            Export-Csv -NoTypeInformation -Path (Join-Path $ReportDir '08-scheduled-task-failures.csv')
    }

    Try-Run 'HID devices' {
        Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object { $_.PNPClass -eq 'HIDClass' -or $_.Name -match 'scanner|barcode|HID' } |
            Select-Object Name, Manufacturer, Status, DeviceID |
            Format-Table -AutoSize | Out-String |
            Set-Content (Join-Path $ReportDir '08-hid-devices.txt')
    }

    # -----------------------------------------------------------------------
    # 9. Network: adapters, TCP, DNS client, plus targeted probes
    # -----------------------------------------------------------------------
    Write-Section '9. Network diagnostics'
    Try-Run 'IP / adapters / TCP / DNS client' {
        Get-NetIPConfiguration -Detailed -ErrorAction SilentlyContinue |
            Out-File (Join-Path $ReportDir '09-ipconfig.txt') -Encoding UTF8
        Get-NetAdapter -ErrorAction SilentlyContinue |
            Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress |
            Export-Csv -NoTypeInformation -Path (Join-Path $ReportDir '09-adapters.csv')
        Get-NetTCPConnection -ErrorAction SilentlyContinue |
            Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess |
            Export-Csv -NoTypeInformation -Path (Join-Path $ReportDir '09-tcp-connections.csv')
        Get-DnsClientServerAddress -ErrorAction SilentlyContinue |
            Select-Object InterfaceAlias, AddressFamily, @{n='Servers';e={ ($_.ServerAddresses -join ', ') }} |
            Export-Csv -NoTypeInformation -Path (Join-Path $ReportDir '09-dns-client.csv')
    }

    Try-Run 'WiFi state' {
        $netshOut = & netsh wlan show interfaces 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0 -or $netshOut -match 'no wireless interface') {
            'No WiFi interfaces present.' |
                Set-Content (Join-Path $ReportDir '09-wifi.txt')
            return
        }
        $sb = New-Object System.Text.StringBuilder
        $null = $sb.AppendLine('--- netsh wlan show interfaces ---')
        $null = $sb.AppendLine($netshOut)
        $null = $sb.AppendLine('--- netsh wlan show profiles ---')
        $null = $sb.AppendLine((& netsh wlan show profiles 2>&1 | Out-String))
        $null = $sb.AppendLine('--- netsh wlan show networks mode=bssid ---')
        $null = $sb.AppendLine((& netsh wlan show networks mode=bssid 2>&1 | Out-String))
        Save-Text '09-wifi.txt' $sb.ToString()

        if ($netshOut -match 'Signal\s*:\s*(\d+)%') {
            $signal = [int]$Matches[1]
            if ($signal -lt 40) {
                Add-Summary 'WARN' "WiFi signal weak ($signal%)."
            } else {
                Add-Summary 'OK' "WiFi signal $signal%."
            }
        }
    }

    if ($CaptureNetSeconds -gt 0) {
        if (-not $isAdmin) {
            Add-Summary 'WARN' "Network capture skipped: -CaptureNetSeconds $CaptureNetSeconds requested but not elevated."
        } else {
            Try-Run "Network capture ($CaptureNetSeconds s)" {
                $etl = Join-Path $ReportDir '09-network-capture.etl'
                Write-Host "  Capturing network for $CaptureNetSeconds seconds..." -ForegroundColor Yellow
                & netsh trace start capture=yes tracefile=$etl maxsize=200 overwrite=yes 2>&1 | Out-Null
                Start-Sleep -Seconds $CaptureNetSeconds
                & netsh trace stop 2>&1 | Out-Null
                if (Test-Path $etl) {
                    $sizeMb = [math]::Round((Get-Item $etl).Length / 1MB, 1)
                    Add-Summary 'OK' "Captured ${sizeMb} MB of network trace (09-network-capture.etl)."
                } else {
                    Add-Summary 'FAIL' 'Network capture produced no .etl file.'
                }
            }
        }
    }

    Try-Run 'DNS for endpoints' {
        $hosts = @()
        foreach ($u in $Endpoints) {
            try { $hosts += ([Uri]$u).Host } catch {}
        }
        $hosts = $hosts | Sort-Object -Unique
        $rows = foreach ($h in $hosts) {
            try {
                $r = Resolve-DnsName -Name $h -Type A -ErrorAction Stop -DnsOnly |
                     Where-Object { $_.IPAddress } | Select-Object -First 3
                [PSCustomObject]@{ Host = $h; IPs = ($r.IPAddress -join ', '); Error = '' }
            } catch {
                Add-Summary 'FAIL' "DNS lookup failed for $h : $($_.Exception.Message)"
                [PSCustomObject]@{ Host = $h; IPs = ''; Error = $_.Exception.Message }
            }
        }
        if ($rows) {
            $rows | Format-Table -AutoSize -Wrap | Out-String |
                Set-Content (Join-Path $ReportDir '09-dns-endpoints.txt')
        } else {
            'No endpoints supplied; endpoint-DNS section skipped.' |
                Set-Content (Join-Path $ReportDir '09-dns-endpoints.txt')
        }
    }

    Try-Run 'Proxy' {
        $sb = New-Object System.Text.StringBuilder
        $null = $sb.AppendLine('--- netsh winhttp show proxy ---')
        $null = $sb.AppendLine((& netsh winhttp show proxy 2>&1 | Out-String))
        $null = $sb.AppendLine('--- env vars ---')
        foreach ($v in 'HTTP_PROXY','HTTPS_PROXY','NO_PROXY','http_proxy','https_proxy','no_proxy') {
            $val = [Environment]::GetEnvironmentVariable($v)
            $null = $sb.AppendLine("$v = $val")
        }
        $null = $sb.AppendLine('--- IE / WinINET (per-user) ---')
        try {
            $reg = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
            $null = $sb.AppendLine("ProxyEnable = $($reg.ProxyEnable)")
            $null = $sb.AppendLine("ProxyServer = $($reg.ProxyServer)")
            $null = $sb.AppendLine("AutoConfigURL = $($reg.AutoConfigURL)")
            if ($reg.ProxyEnable -eq 1) {
                Add-Summary 'WARN' "WinINET proxy is enabled ($($reg.ProxyServer)); requests may be intercepted."
            }
        } catch {
            $null = $sb.AppendLine("(could not read: $($_.Exception.Message))")
        }
        Save-Text '09-proxy.txt' $sb.ToString()
    }

    Try-Run 'Time skew' {
        $out = & w32tm /query /status 2>&1 | Out-String
        Save-Text '09-time.txt' $out
        $local = [DateTimeOffset]::UtcNow
        try {
            $hdr = (Invoke-WebRequest 'https://www.google.com' -UseBasicParsing -TimeoutSec 8 -Method Head).Headers['Date']
            if ($hdr) {
                $remote = [DateTimeOffset]::Parse($hdr)
                $skew = ($local - $remote).TotalSeconds
                $isoFormat = 'o'
                $localStr  = $local.ToString($isoFormat)
                $remoteStr = $remote.ToString($isoFormat)
                Add-Content (Join-Path $ReportDir '09-time.txt') "`nLocal: $localStr`nRemote (google): $remoteStr`nSkew (seconds): $skew"
                if ([math]::Abs($skew) -gt 60) {
                    Add-Summary 'FAIL' "Clock skew is $([int]$skew)s vs google.com - TLS may fail."
                } else {
                    Add-Summary 'OK' "Clock skew $([int]$skew)s within tolerance."
                }
            }
        } catch {
            Add-Content (Join-Path $ReportDir '09-time.txt') "`nSkew check failed: $($_.Exception.Message)"
        }
    }

    Try-Run 'Firewall profiles' {
        Get-NetFirewallProfile -ErrorAction SilentlyContinue |
            Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction |
            Format-Table -AutoSize | Out-String |
            Set-Content (Join-Path $ReportDir '09-firewall.txt')
    }

    if ($Endpoints -and $Endpoints.Count -gt 0) {
        Try-Run 'HTTP probes' {
            $results = foreach ($url in $Endpoints) {
                $sw = [Diagnostics.Stopwatch]::StartNew()
                try {
                    $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
                    $sw.Stop()
                    [PSCustomObject]@{ Url=$url; Status=$resp.StatusCode; TimeMs=$sw.ElapsedMilliseconds; Error='' }
                } catch {
                    $sw.Stop()
                    [PSCustomObject]@{ Url=$url; Status=''; TimeMs=$sw.ElapsedMilliseconds; Error=$_.Exception.Message }
                }
            }
            $results | Format-Table -AutoSize -Wrap | Out-String |
                Set-Content (Join-Path $ReportDir '09-http-probes.txt')

            $reachable = ($results | Where-Object { $_.Status }).Count
            if ($reachable -eq $results.Count) {
                Add-Summary 'OK' "All $reachable endpoints reachable."
            } elseif ($reachable -eq 0) {
                Add-Summary 'FAIL' 'No endpoints reachable - check network/firewall/proxy.'
            } else {
                Add-Summary 'WARN' "$reachable of $($results.Count) endpoints reachable; partial outage."
            }
        }
    }

    # -----------------------------------------------------------------------
    # 10. System health: DISM CheckHealth (admin), systeminfo
    # -----------------------------------------------------------------------
    Write-Section '10. System health'
    if ($isAdmin) {
        Try-Run 'DISM CheckHealth' {
            $dism = & DISM.exe /Online /Cleanup-Image /CheckHealth 2>&1
            Save-Text '10-dism-checkhealth.txt' ($dism -join "`r`n")
            if ($dism -match 'No component store corruption detected') {
                Add-Summary 'OK' 'DISM: no component store corruption.'
            } elseif ($dism -match 'repairable|corruption') {
                Add-Summary 'WARN' 'DISM reports component store issues - run /ScanHealth /RestoreHealth.'
            }
        }
    } else {
        'DISM CheckHealth skipped (requires elevation).' |
            Set-Content (Join-Path $ReportDir '10-dism-checkhealth.txt')
    }

    Try-Run 'systeminfo' {
        & systeminfo.exe 2>&1 | Out-File (Join-Path $ReportDir '10-systeminfo.txt') -Encoding UTF8
    }
}

# ---------------------------------------------------------------------------
# Standalone entry point. Skipped when dot-sourced.
# ---------------------------------------------------------------------------

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $ReportDir) {
        $ReportDir = Initialize-Report -OutputRoot $OutputRoot -ProjectName $ProjectName
    } else {
        $script:reportDir = $ReportDir
        if (-not $script:summary) { $script:summary = New-Object System.Collections.ArrayList }
    }
    Invoke-SystemDiagnostics -ReportDir $ReportDir -EventLogDays $EventLogDays `
        -Endpoints $Endpoints -WerKeywords $WerKeywords -IncludeMiniDumps:$IncludeMiniDumps `
        -CaptureNetSeconds $CaptureNetSeconds
    if (-not $NoFinalize) {
        Finalize-Report -ReportDir $ReportDir -Sanitize:$Sanitize
    }
}
