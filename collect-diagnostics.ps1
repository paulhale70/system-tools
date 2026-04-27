<#
.SYNOPSIS
    Collects diagnostic and crash information for the Media Inventory Scanner.

.DESCRIPTION
    Gathers system info, Python and dependency state, app file inventory,
    SQLite database metadata, recent Windows Application/System event log
    errors, Windows Error Reporting (WER) crash artifacts, and API
    connectivity checks. Everything is written to a timestamped folder on the
    Desktop and zipped for easy sharing.

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
    }
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

    foreach ($cmd in 'python','py','python3') {
        $exe = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($exe) {
            $null = $pyOut.AppendLine("--- $cmd ($($exe.Source)) ---")
            $null = $pyOut.AppendLine((& $cmd --version 2>&1 | Out-String).Trim())
            $null = $pyOut.AppendLine((& $cmd -c "import sys; print(sys.executable); print(sys.version); print(sys.path)" 2>&1 | Out-String))
        }
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
# 4. SQLite database
# ---------------------------------------------------------------------------
Write-Section '4. SQLite database'
Try-Run 'Database info' {
    $dbPath = Join-Path $env:USERPROFILE 'media_inventory.db'
    if (Test-Path $dbPath) {
        $f = Get-Item $dbPath
        $info = [PSCustomObject]@{
            Path          = $f.FullName
            SizeBytes     = $f.Length
            SizeMB        = [math]::Round($f.Length/1MB, 3)
            LastWriteTime = $f.LastWriteTime
            CreationTime  = $f.CreationTime
            SHA256        = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
        }
        $info | Format-List | Out-String | Set-Content (Join-Path $reportDir '04-database.txt')
    } else {
        "Database not found at $dbPath" | Set-Content (Join-Path $reportDir '04-database.txt')
    }
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
# 7. Network / API connectivity
# ---------------------------------------------------------------------------
Write-Section '7. API connectivity'
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
            [PSCustomObject]@{
                Url     = $url
                Status  = $resp.StatusCode
                TimeMs  = $sw.ElapsedMilliseconds
                Error   = ''
            }
        } catch {
            $sw.Stop()
            [PSCustomObject]@{
                Url     = $url
                Status  = ''
                TimeMs  = $sw.ElapsedMilliseconds
                Error   = $_.Exception.Message
            }
        }
    }
    $results | Format-Table -AutoSize -Wrap | Out-String |
        Set-Content (Join-Path $reportDir '07-api-connectivity.txt')
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
# 9. Zip everything up
# ---------------------------------------------------------------------------
Stop-Transcript | Out-Null

$zipPath = "$reportDir.zip"
Compress-Archive -Path (Join-Path $reportDir '*') -DestinationPath $zipPath -Force

Write-Host ''
Write-Host "Diagnostics collected:" -ForegroundColor Green
Write-Host "  Folder: $reportDir"
Write-Host "  Zip:    $zipPath"
Write-Host ''
Write-Host 'Send the zip file when reporting an issue.'
