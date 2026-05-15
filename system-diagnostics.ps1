<#
.SYNOPSIS
    Generic Windows diagnostic collector. Project-agnostic.

.DESCRIPTION
    Gathers system info, Python and dependency state, project file
    inventory, recent Windows Application/System event log errors,
    Windows Error Reporting (WER) crash artifacts, and network
    diagnostics (DNS, proxy, time skew, firewall, optional HTTP probes).
    Writes a top-level SUMMARY.txt with green/yellow/red verdicts, then
    zips everything for easy sharing.

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
    Regex of substrings to filter Report.wer files by (matches process
    or module name). Default: 'python|pythonw'.

.PARAMETER ReportDir
    Reuse an existing report folder instead of creating a new one.

.PARAMETER NoFinalize
    Skip writing SUMMARY.txt and zipping. Useful when chaining with an
    app-specific diagnostic script.
#>

[CmdletBinding()]
param(
    [string]$OutputRoot   = [Environment]::GetFolderPath('Desktop'),
    [int]$EventLogDays    = 7,
    [string]$ProjectName  = 'System',
    [string[]]$Endpoints  = @(),
    [string]$WerKeywords  = 'python|pythonw',
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

function Initialize-Report {
    param(
        [string]$OutputRoot  = [Environment]::GetFolderPath('Desktop'),
        [string]$ProjectName = 'System'
    )
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dir = Join-Path $OutputRoot "$ProjectName-Diagnostics-$timestamp"
    $null = New-Item -ItemType Directory -Path $dir -Force

    $script:reportDir = $dir
    $script:summary   = New-Object System.Collections.ArrayList
    $script:transcript = Join-Path $dir 'collector.log'
    Start-Transcript -Path $script:transcript -Append | Out-Null
    return $dir
}

function Finalize-Report {
    param([string]$ReportDir = $script:reportDir)

    $summaryPath = Join-Path $ReportDir '00-SUMMARY.txt'
    $generated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $header = @(
        "Diagnostics summary"
        "Generated: $generated"
        "Host: $env:COMPUTERNAME  User: $env:USERNAME"
        ('-' * 60)
        ''
    )
    $counts = $script:summary | Group-Object { ($_ -split ' ',2)[0] } |
        ForEach-Object { "{0,-7} {1}" -f $_.Name, $_.Count }
    ($header + $counts + '' + ($script:summary | Sort-Object)) -join "`r`n" |
        Set-Content $summaryPath -Encoding UTF8

    Stop-Transcript | Out-Null

    $zipPath = "$ReportDir.zip"
    Compress-Archive -Path (Join-Path $ReportDir '*') -DestinationPath $zipPath -Force -CompressionLevel Optimal

    Write-Host ''
    Write-Host 'Diagnostics collected:' -ForegroundColor Green
    Write-Host "  Folder: $ReportDir"
    Write-Host "  Zip:    $zipPath"
    Write-Host ''
    Write-Host 'Top-level verdicts:'
    Get-Content $summaryPath | Select-Object -First 40 | ForEach-Object { Write-Host "  $_" }

    if (-not $env:CI) {
        Try-Run 'Open folder' { Start-Process explorer.exe $ReportDir }
    }
}

# ---------------------------------------------------------------------------
# System diagnostic sections
# ---------------------------------------------------------------------------

function Invoke-SystemDiagnostics {
    param(
        [string]$ReportDir   = $script:reportDir,
        [int]$EventLogDays   = 7,
        [string[]]$Endpoints = @(),
        [string]$WerKeywords = 'python|pythonw'
    )
    $script:reportDir = $ReportDir

    # -----------------------------------------------------------------------
    # 1. System information
    # -----------------------------------------------------------------------
    Write-Section '1. System information'
    Try-Run 'System info' {
        $os   = Get-CimInstance Win32_OperatingSystem
        $cs   = Get-CimInstance Win32_ComputerSystem
        $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
        $bios = Get-CimInstance Win32_BIOS

        $info = [PSCustomObject]@{
            Timestamp         = (Get-Date).ToString('o')
            ComputerName      = $env:COMPUTERNAME
            UserName          = $env:USERNAME
            OSCaption         = $os.Caption
            OSVersion         = $os.Version
            OSBuild           = $os.BuildNumber
            OSArchitecture    = $os.OSArchitecture
            InstallDate       = $os.InstallDate
            LastBootUpTime    = $os.LastBootUpTime
            Manufacturer      = $cs.Manufacturer
            Model             = $cs.Model
            TotalMemoryGB     = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
            FreeMemoryGB      = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
            CPU               = $cpu.Name
            CPUCores          = $cpu.NumberOfCores
            CPULogical        = $cpu.NumberOfLogicalProcessors
            BIOSVersion       = $bios.SMBIOSBIOSVersion
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
    # 3. Project files
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

        # Git state (if any)
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
    # 5. Event log errors and warnings
    # -----------------------------------------------------------------------
    Write-Section '5. Event log (Application + System)'
    Try-Run 'Event log' {
        $since = (Get-Date).AddDays(-$EventLogDays)
        foreach ($log in 'Application','System') {
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

    # -----------------------------------------------------------------------
    # 6. Windows Error Reporting (WER) crash artifacts
    # -----------------------------------------------------------------------
    Write-Section '6. Windows Error Reporting'
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
                Format-Table -AutoSize | Out-String |
                Set-Content (Join-Path $ReportDir '06-crash-dumps.txt')
        } else {
            'No recent crash dumps found.' |
                Set-Content (Join-Path $ReportDir '06-crash-dumps.txt')
        }
    }

    # -----------------------------------------------------------------------
    # 7. Network: DNS, proxy, time, firewall, optional HTTP probes
    # -----------------------------------------------------------------------
    Write-Section '7. Network diagnostics'
    Try-Run 'DNS' {
        # Derive hostnames from endpoint URLs.
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
                Set-Content (Join-Path $ReportDir '07-dns.txt')
        } else {
            'No endpoints supplied; DNS section skipped.' |
                Set-Content (Join-Path $ReportDir '07-dns.txt')
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
        Save-Text '07-proxy.txt' $sb.ToString()
    }

    Try-Run 'Time skew' {
        $out = & w32tm /query /status 2>&1 | Out-String
        Save-Text '07-time.txt' $out
        $local = [DateTimeOffset]::UtcNow
        try {
            $hdr = (Invoke-WebRequest 'https://www.google.com' -UseBasicParsing -TimeoutSec 8 -Method Head).Headers['Date']
            if ($hdr) {
                $remote = [DateTimeOffset]::Parse($hdr)
                $skew = ($local - $remote).TotalSeconds
                $isoFormat = 'o'
                $localStr  = $local.ToString($isoFormat)
                $remoteStr = $remote.ToString($isoFormat)
                Add-Content (Join-Path $ReportDir '07-time.txt') "`nLocal: $localStr`nRemote (google): $remoteStr`nSkew (seconds): $skew"
                if ([math]::Abs($skew) -gt 60) {
                    Add-Summary 'FAIL' "Clock skew is $([int]$skew)s vs google.com - TLS may fail."
                } else {
                    Add-Summary 'OK' "Clock skew $([int]$skew)s within tolerance."
                }
            }
        } catch {
            Add-Content (Join-Path $ReportDir '07-time.txt') "`nSkew check failed: $($_.Exception.Message)"
        }
    }

    Try-Run 'Firewall profiles' {
        Get-NetFirewallProfile -ErrorAction SilentlyContinue |
            Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction |
            Format-Table -AutoSize | Out-String |
            Set-Content (Join-Path $ReportDir '07-firewall.txt')
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
                Set-Content (Join-Path $ReportDir '07-http-probes.txt')

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
    # 8. Running Python processes + USB HID devices
    # -----------------------------------------------------------------------
    Write-Section '8. Processes + USB HID devices'
    Try-Run 'Processes' {
        Get-Process -Name 'python','pythonw' -ErrorAction SilentlyContinue |
            Select-Object Id, ProcessName, StartTime,
                @{n='WorkingSetMB';e={[math]::Round($_.WorkingSet64/1MB,1)}},
                @{n='CPUSeconds';e={[math]::Round($_.CPU,1)}},
                Path |
            Format-Table -AutoSize | Out-String |
            Set-Content (Join-Path $ReportDir '08-python-processes.txt')

        Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object { $_.PNPClass -eq 'HIDClass' -or $_.Name -match 'scanner|barcode|HID' } |
            Select-Object Name, Manufacturer, Status, DeviceID |
            Format-Table -AutoSize | Out-String |
            Set-Content (Join-Path $ReportDir '08-hid-devices.txt')
    }
}

# ---------------------------------------------------------------------------
# Standalone entry point. Skipped when dot-sourced ($MyInvocation.InvocationName -eq '.').
# ---------------------------------------------------------------------------

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $ReportDir) {
        $ReportDir = Initialize-Report -OutputRoot $OutputRoot -ProjectName $ProjectName
    } else {
        $script:reportDir = $ReportDir
        if (-not $script:summary) { $script:summary = New-Object System.Collections.ArrayList }
    }
    Invoke-SystemDiagnostics -ReportDir $ReportDir -EventLogDays $EventLogDays `
        -Endpoints $Endpoints -WerKeywords $WerKeywords
    if (-not $NoFinalize) {
        Finalize-Report -ReportDir $ReportDir
    }
}
