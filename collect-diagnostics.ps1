<#
.SYNOPSIS
    Collects diagnostic and crash information for the Media Inventory Scanner.

.DESCRIPTION
    Gathers system info, Python and dependency state, app file inventory,
    SQLite database health (resolved path, integrity check, row counts),
    recent Windows Application/System event log errors, Windows Error
    Reporting (WER) crash artifacts, network diagnostics (DNS, proxy, time
    skew, API reachability), and an end-to-end lookup pipeline test.
    Writes a top-level SUMMARY.txt with green/yellow/red verdicts, then
    zips everything for easy sharing.

    Run from the project folder:
        powershell -ExecutionPolicy Bypass -File .\collect-diagnostics.ps1

.PARAMETER OutputRoot
    Directory where the report folder and zip are written.
    Defaults to the current user's Desktop.

.PARAMETER EventLogDays
    How many days of Application/System event log entries to collect.
    Default: 7.
#>

[CmdletBinding()]
param(
    [string]$OutputRoot = [Environment]::GetFolderPath('Desktop'),
    [int]$EventLogDays = 7
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$timestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportDir  = Join-Path $OutputRoot "MediaInventory-Diagnostics-$timestamp"
$null = New-Item -ItemType Directory -Path $reportDir -Force

$transcript = Join-Path $reportDir 'collector.log'
Start-Transcript -Path $transcript -Append | Out-Null

function Write-Section($title) {
    Write-Host ''
    Write-Host ('=' * 70)
    Write-Host $title
    Write-Host ('=' * 70)
}

function Save-Text($name, $content) {
    $path = Join-Path $reportDir $name
    $content | Out-File -FilePath $path -Encoding UTF8
}

function Try-Run($label, [scriptblock]$block) {
    try {
        & $block
    } catch {
        Write-Warning "$label failed: $($_.Exception.Message)"
        Add-Summary 'FAIL' "$label : $($_.Exception.Message)"
    }
}

$script:summary = New-Object System.Collections.ArrayList

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

function Find-AppRoot {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if (Test-Path (Join-Path (Get-Location) 'main.py')) { return (Get-Location).Path }
    return $null
}

function Invoke-PythonScript($appRoot, $scriptPath) {
    try {
        Push-Location $appRoot
        $out = & python $scriptPath 2>&1 | Out-String
        $exit = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    [PSCustomObject]@{ Output = $out; ExitCode = $exit }
}

# ---------------------------------------------------------------------------
# 1. System information
# ---------------------------------------------------------------------------
Write-Section '1. System information'
Try-Run 'System info' {
    $os   = Get-CimInstance Win32_OperatingSystem
    $cs   = Get-CimInstance Win32_ComputerSystem
    $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
    $bios = Get-CimInstance Win32_BIOS

    $info = [PSCustomObject]@{
        Timestamp        = (Get-Date).ToString('o')
        ComputerName     = $env:COMPUTERNAME
        UserName         = $env:USERNAME
        OSCaption        = $os.Caption
        OSVersion        = $os.Version
        OSBuild          = $os.BuildNumber
        OSArchitecture   = $os.OSArchitecture
        InstallDate      = $os.InstallDate
        LastBootUpTime   = $os.LastBootUpTime
        Manufacturer     = $cs.Manufacturer
        Model            = $cs.Model
        TotalMemoryGB    = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
        FreeMemoryGB     = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        CPU              = $cpu.Name
        CPUCores         = $cpu.NumberOfCores
        CPULogical       = $cpu.NumberOfLogicalProcessors
        BIOSVersion      = $bios.SMBIOSBIOSVersion
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        Culture          = (Get-Culture).Name
        TimeZone         = (Get-TimeZone).Id
    }
    $info | Format-List | Out-String | Set-Content (Join-Path $reportDir '01-system-info.txt')

    Get-PSDrive -PSProvider FileSystem |
        Select-Object Name, @{n='UsedGB';e={[math]::Round($_.Used/1GB,2)}}, @{n='FreeGB';e={[math]::Round($_.Free/1GB,2)}}, Root |
        Format-Table -AutoSize | Out-String |
        Set-Content (Join-Path $reportDir '01-disks.txt')
}

# ---------------------------------------------------------------------------
# 2. Python + dependencies
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# 3. Application files
# ---------------------------------------------------------------------------
Write-Section '3. Application files'
Try-Run 'App inventory' {
    $appRoot = $PSScriptRoot
    if (-not $appRoot) { $appRoot = Get-Location }

    $files = Get-ChildItem -Path $appRoot -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.Length -lt 50MB }

    $files |
        Select-Object FullName, Length, LastWriteTime,
            @{n='SHA256';e={ (Get-FileHash $_.FullName -Algorithm SHA256).Hash }} |
        Format-Table -AutoSize | Out-String |
        Set-Content (Join-Path $reportDir '03-app-files.txt')

    if (Test-Path (Join-Path $appRoot 'requirements.txt')) {
        Copy-Item (Join-Path $appRoot 'requirements.txt') (Join-Path $reportDir '03-requirements.txt') -Force
    }
}

# ---------------------------------------------------------------------------
# 4. SQLite database (resolved path, integrity, row counts)
# ---------------------------------------------------------------------------
Write-Section '4. SQLite database'
Try-Run 'Database info' {
    $appRoot = Find-AppRoot
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
        Add-Summary 'WARN' 'Run collect-diagnostics.ps1 from the project folder for full DB diagnostics.'
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

        # OneDrive / Files-On-Demand placeholder check.
        # FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS = 0x400000, RECALL_ON_OPEN = 0x40000
        $rawAttr = [int]$f.Attributes
        if (($rawAttr -band 0x400000) -or ($rawAttr -band 0x40000)) {
            Add-Summary 'FAIL' "DB file is a cloud placeholder (not fully downloaded): $resolvedDb"
        }
    }

    Save-Text '04-database.txt' $report.ToString()
}

# ---------------------------------------------------------------------------
# 5. Event log errors and warnings
# ---------------------------------------------------------------------------
Write-Section '5. Event log (Application + System)'
Try-Run 'Event log' {
    $since = (Get-Date).AddDays(-$EventLogDays)
    foreach ($log in 'Application','System') {
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = $log
            Level     = 1,2,3   # Critical, Error, Warning
            StartTime = $since
        } -ErrorAction SilentlyContinue

        if ($events) {
            $events |
                Select-Object TimeCreated, LevelDisplayName, ProviderName, Id,
                    @{n='Message';e={ ($_.Message -replace '\s+',' ').Substring(0, [Math]::Min(500, $_.Message.Length)) }} |
                Sort-Object TimeCreated -Descending |
                ConvertTo-Csv -NoTypeInformation |
                Set-Content (Join-Path $reportDir "05-events-$log.csv")
        } else {
            "No $log events in the last $EventLogDays days." |
                Set-Content (Join-Path $reportDir "05-events-$log.csv")
        }
    }
}

# ---------------------------------------------------------------------------
# 6. Windows Error Reporting (WER) crash artifacts
# ---------------------------------------------------------------------------
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
                    $txt -match 'python|pythonw|main\.py|media_inventory'
                }
        }
    }

    if ($hits) {
        $werDir = Join-Path $reportDir 'wer-reports'
        $null = New-Item -ItemType Directory -Path $werDir -Force
        foreach ($h in $hits) {
            $dest = Join-Path $werDir ($h.Directory.Name + '_' + $h.Name)
            Copy-Item $h.FullName $dest -Force
        }
        "Copied $($hits.Count) Python-related WER reports." |
            Set-Content (Join-Path $reportDir '06-wer.txt')
    } else {
        'No Python-related WER reports found.' |
            Set-Content (Join-Path $reportDir '06-wer.txt')
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
            Set-Content (Join-Path $reportDir '06-crash-dumps.txt')
    } else {
        'No recent crash dumps found.' |
            Set-Content (Join-Path $reportDir '06-crash-dumps.txt')
    }
}

# ---------------------------------------------------------------------------
# 7. Network: DNS, proxy, time, API connectivity
# ---------------------------------------------------------------------------
Write-Section '7. Network diagnostics'
Try-Run 'DNS' {
    $hosts = 'api.upcitemdb.com','www.googleapis.com','openlibrary.org','musicbrainz.org'
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
    $rows | Format-Table -AutoSize -Wrap | Out-String |
        Set-Content (Join-Path $reportDir '07-dns.txt')
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
            Add-Content (Join-Path $reportDir '07-time.txt') "`nLocal: $localStr`nRemote (google): $remoteStr`nSkew (seconds): $skew"
            if ([math]::Abs($skew) -gt 60) {
                Add-Summary 'FAIL' "Clock skew is $([int]$skew)s vs google.com - TLS to APIs may fail."
            } else {
                Add-Summary 'OK' "Clock skew $([int]$skew)s within tolerance."
            }
        }
    } catch {
        Add-Content (Join-Path $reportDir '07-time.txt') "`nSkew check failed: $($_.Exception.Message)"
    }
}

Try-Run 'Firewall profiles' {
    Get-NetFirewallProfile -ErrorAction SilentlyContinue |
        Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction |
        Format-Table -AutoSize | Out-String |
        Set-Content (Join-Path $reportDir '07-firewall.txt')
}

Try-Run 'API checks' {
    $endpoints = @(
        'https://api.upcitemdb.com/prod/trial/lookup?upc=000000000000'
        'https://www.googleapis.com/books/v1/volumes?q=isbn:9780000000000'
        'https://openlibrary.org/api/books?bibkeys=ISBN:9780000000000&format=json'
        'https://musicbrainz.org/ws/2/release/?query=barcode:000000000000&fmt=json'
    )
    $results = foreach ($url in $endpoints) {
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
        Set-Content (Join-Path $reportDir '07-api-connectivity.txt')

    $reachable = ($results | Where-Object { $_.Status }).Count
    if ($reachable -eq $results.Count) {
        Add-Summary 'OK' "All $reachable lookup APIs reachable."
    } elseif ($reachable -eq 0) {
        Add-Summary 'FAIL' 'No lookup APIs reachable - check network/firewall/proxy.'
    } else {
        Add-Summary 'WARN' "$reachable of $($results.Count) lookup APIs reachable; partial outage or rate limit."
    }
}

# ---------------------------------------------------------------------------
# 8. Running Python processes + USB HID devices (scanner)
# ---------------------------------------------------------------------------
Write-Section '8. Processes + USB HID devices'
Try-Run 'Processes' {
    Get-Process -Name 'python','pythonw' -ErrorAction SilentlyContinue |
        Select-Object Id, ProcessName, StartTime,
            @{n='WorkingSetMB';e={[math]::Round($_.WorkingSet64/1MB,1)}},
            @{n='CPUSeconds';e={[math]::Round($_.CPU,1)}},
            Path |
        Format-Table -AutoSize | Out-String |
        Set-Content (Join-Path $reportDir '08-python-processes.txt')

    Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
        Where-Object { $_.PNPClass -eq 'HIDClass' -or $_.Name -match 'scanner|barcode|HID' } |
        Select-Object Name, Manufacturer, Status, DeviceID |
        Format-Table -AutoSize | Out-String |
        Set-Content (Join-Path $reportDir '08-hid-devices.txt')
}

# ---------------------------------------------------------------------------
# 8b. Application log (set by applog.py, next to the DB)
# ---------------------------------------------------------------------------
Write-Section '8b. Application log'
Try-Run 'App log' {
    $candidates = @()
    if ($resolvedDb) { $candidates += (Join-Path (Split-Path $resolvedDb -Parent) 'media_inventory.log') }
    $candidates += (Join-Path $env:USERPROFILE 'media_inventory.log')
    $logPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($logPath) {
        Copy-Item $logPath (Join-Path $reportDir '08-app.log') -Force
        # Also copy any rotated backups (.log.1 .. .log.5)
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

# ---------------------------------------------------------------------------
# 9. End-to-end lookup pipeline test
# ---------------------------------------------------------------------------
Write-Section '9. Lookup pipeline test'
Try-Run 'Lookup pipeline' {
    $appRoot = Find-AppRoot
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

# ---------------------------------------------------------------------------
# 10. Write SUMMARY.txt and zip everything up
# ---------------------------------------------------------------------------
$summaryPath = Join-Path $reportDir '00-SUMMARY.txt'
$generated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
$header = @(
    "Media Inventory Scanner - diagnostics summary"
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

$zipPath = "$reportDir.zip"
Compress-Archive -Path (Join-Path $reportDir '*') -DestinationPath $zipPath -Force -CompressionLevel Optimal

Write-Host ''
Write-Host 'Diagnostics collected:' -ForegroundColor Green
Write-Host "  Folder: $reportDir"
Write-Host "  Zip:    $zipPath"
Write-Host ''
Write-Host 'Top-level verdicts:'
Get-Content $summaryPath | Select-Object -First 40 | ForEach-Object { Write-Host "  $_" }
Write-Host ''
Write-Host 'Send the zip file when reporting an issue.'

if (-not $env:CI) {
    Try-Run 'Open folder' { Start-Process explorer.exe $reportDir }
}
