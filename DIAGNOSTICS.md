# System-tools Diagnostics

A set of PowerShell scripts that collect Windows diagnostic information,
turn it into a readable HTML report with plain-English fix suggestions,
and track trends across past runs so recurring problems become obvious.

---

## What's in the box

| Script | What it does |
| --- | --- |
| `system-diagnostics.ps1` | Generic Windows collector. Project-agnostic. Run it in any folder. |
| `app-diagnostics.ps1`    | Media Inventory Scanner wrapper. Adds DB / log / lookup checks. |
| `diff-diagnostics.ps1`   | Compare two diagnostic reports. Shows what changed since the last run. |
| `trends-diagnostics.ps1` | View trends across all past runs (recurring issues, history). |
| `run-diagnostics.bat`    | Double-clickable launcher for non-technical users. |
| `install.ps1`            | Copy `system-diagnostics.ps1` to `~/bin/` and add it to PATH. |

---

## Quick start

### For yourself

```powershell
git clone https://github.com/paulhale70/System-tools.git
cd System-tools
.\system-diagnostics.ps1
```

The script runs through ten or so sections, writes a folder to your
Desktop, and opens `00-summary.html` in your browser.

To make it available from any folder:

```powershell
.\install.ps1
```

### For someone you're helping (non-technical)

Send them `run-diagnostics.bat`. They double-click it; in 2-5 minutes
they get a zip on their Desktop they can email back. See
[INSTRUCTIONS-FOR-USERS.md](INSTRUCTIONS-FOR-USERS.md) for a
copy-pasteable email-body version.

---

## What gets collected

| Section | Files |
| --- | --- |
| System info, disks | `01-system-info.txt`, `01-disks.txt` |
| Python install + pip | `02-python.txt` |
| Project files + git state | `03-project-files.txt`, `03-git.txt` |
| Installed updates | `04-hotfixes.csv` |
| Event logs (System / Application / Setup) | `05-events-*.csv` |
| Bug-checks + app crashes + reliability records | `05-bugchecks.csv`, `05-app-crashes.csv`, `05-reliability.csv` |
| WER, LiveKernelReports, minidumps, MEMORY.DMP | `06-*` |
| Crash-dump auto-analysis (if Debugging Tools installed) | `06-dump-analysis.txt` |
| Drivers, disks + SMART, memory modules, battery | `07-*` |
| Processes, services, startup, scheduled tasks, HID | `08-*` |
| Network: adapters, TCP, DNS, WiFi, proxy, time, firewall, HTTP probes | `09-*` |
| DISM CheckHealth, systeminfo | `10-*` |
| Top-level summary + HTML report | `00-SUMMARY.txt`, `00-summary.html` |

**Not collected**: passwords, documents, browser history, file contents.

---

## Highlights

**Plain-English fixes.** The summary scans verdicts for known patterns
(BSODs, unhealthy disk, clock skew, OneDrive placeholder DB, DISM
corruption, proxy enabled, missing Python, etc.) and prints
remediation steps in the HTML report and `00-SUMMARY.txt`.

**Trend tracking.** Each run is appended to
`%USERPROFILE%\diagnostics-history.json`. The HTML report shows:
- New verdicts since the previous run
- Resolved verdicts
- Verdicts recurring in >=3 of the last 5 runs
- OK / WARN / FAIL counts over the last 10 runs

Use `trends-diagnostics.ps1` to see the full history across hosts and
projects.

**Diff two runs.** When you want to know whether something you tried
made a difference:

```powershell
.\diff-diagnostics.ps1 -Old "report-monday.zip" -New "report-tuesday.zip"
```

**Crash-dump auto-analysis.** If Windows Debugging Tools (`cdb.exe`) is
installed, the script runs `!analyze -v` against recent minidumps and
saves the bug-check root cause as text.

**PII redaction.** Pass `-Sanitize` to redact username, host name,
USERPROFILE path, MAC addresses, and private IPs from every text file
in the report before zipping. Use when sharing publicly.

**Network capture.** Pass `-CaptureNetSeconds 60` (requires elevation)
to bundle a `netsh trace` `.etl` during a reproduction window.

---

## Common command lines

```powershell
# Default run
.\system-diagnostics.ps1

# Two weeks of event logs, copy crash dumps, sanitize, capture network
.\system-diagnostics.ps1 -EventLogDays 14 -IncludeMiniDumps -Sanitize -CaptureNetSeconds 60

# Tag the report folder with a project name and probe specific endpoints
.\system-diagnostics.ps1 -ProjectName 'social-cross-post' -Endpoints @(
    'https://api.openai.com'
    'https://api.x.com'
)

# Compare last week vs today
.\diff-diagnostics.ps1 -Old (Get-ChildItem ~/Desktop\*-Diagnostics-*.zip | Sort LastWriteTime | Select -First 1).FullName `
                       -New (Get-ChildItem ~/Desktop\*-Diagnostics-*.zip | Sort LastWriteTime -Descending | Select -First 1).FullName

# View trends across all runs
.\trends-diagnostics.ps1

# Same, filtered
.\trends-diagnostics.ps1 -Project MediaInventory -Top 25
```

---

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 (preinstalled) or PowerShell 7
- Some sections need elevation (DISM, network capture, full event log
  coverage). The script reports which sections were skipped if not
  elevated.

---

## Files written outside the report folder

The only file written outside the timestamped report folder is the
history log:

```
%USERPROFILE%\diagnostics-history.json
```

It's local to the machine the script runs on, capped at the last 100
runs, and used only for the trend section. Delete it any time to
reset trends.
