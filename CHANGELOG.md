# Changelog

All notable changes to this repository will be documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versioning follows [Semantic Versioning](https://semver.org/).

## [1.2.0] - 2026-06-10

### diagnostics/

- **Task Manager snapshot** captured on every run. Adds two new
  files to the report:
  - `08-taskmgr-counters.csv` - `Get-Counter` samples of Processor
    Time, Available MBytes, Committed Bytes %, PhysicalDisk % Time,
    Disk Read/Write Bytes/sec, and Network Interface Bytes/sec at
    1-second intervals.
  - `08-taskmgr-processes.csv` - top 30 processes ranked by CPU
    delta over a short window (name, PID, CPU %, working set,
    thread and handle counts, start time, path).
- New `-PerfSampleSeconds N` parameter (default `5`, `0` to skip)
  controls the counter sample duration.
- Summary auto-flags: **WARN** when average CPU > 80% during the
  sample, when free memory dips below 500 MB, when committed
  memory exceeds 90%, or when any single process burned > 50% CPU
  during the window.
- Falls back gracefully on non-English Windows where counter paths
  are localized (records a WARN in the summary and skips the CSV).

### desktop/

- **Run** tab gains a "Task Manager sample: N seconds (0 = off)"
  input beside the existing Network capture control. Value is
  forwarded to `system-diagnostics.ps1` as `-PerfSampleSeconds`.
- `DiagnosticsRunner.Options` grows a `PerfSampleSeconds` field
  (default 5).
- Assembly version bumped to 1.2.0.

### media-inventory/

- `app-diagnostics.ps1` gains `-PerfSampleSeconds` and forwards it
  through to `Invoke-SystemDiagnostics`.

## [1.1.0] - 2026-06-04

### web/ (new)

First release of the standalone HTML SPA dashboard for browsing
diagnostics history.

- One-file `index.html` with no build, server, or install. Open in
  any modern browser; works on Windows, macOS, Linux, and mobile.
- Drag-and-drop or file-picker load of
  `%USERPROFILE%\diagnostics-history.json` (or any compatible JSON
  array). Loaded state cached in `localStorage` so a refresh keeps
  the data; one-click Clear wipes the cache.
- Sidebar navigation with four tabs:
  - **Overview** - totals (Runs / OK / WARN / FAIL), per-host and
    per-project breakdowns, latest-run card.
  - **History** - filterable / searchable list of every run with
    OK/WARN/FAIL count pills, plus a side panel that renders all
    verdicts of the selected run with color-coded pills.
  - **Trends** - Chart.js line chart of OK / WARN / FAIL counts
    over the last 20 runs.
  - **Recurring** - top 25 WARN/FAIL verdicts ranked by frequency
    across the full loaded history.
- Tailwind CSS (via CDN), Alpine.js for reactivity, Chart.js for
  the trend visualization. No npm, no compilation step. View source
  to audit before opening.
- Complements the WPF desktop: desktop *runs* diagnostics, web
  *visualizes* them.

### repo

- Top-level README updated to list four sibling projects (was three).
- README gains a "When to use which" quick-reference table covering
  run / view / compare / bootstrap / help-non-technical scenarios.
- Quick-links section now includes `web/README.md`.

## [1.0.0] - 2026-06-01

First stable release. The repository now hosts three sibling projects.

### desktop/

First public release of the WPF / .NET 8 GUI front-end.
Distributable as a self-contained single-file `.exe` (~75 MB, no
.NET install required). Includes every roadmap item originally
queued for v2:

- Sidebar nav (Run, Diff, Trends, Plugins, Settings).
- **Run** tab: toolbar with `-Sanitize`, `-IncludeMiniDumps`,
  `-CaptureNetSeconds`; history sidebar with OK/WARN/FAIL count
  pills; embedded WebView2 viewer for `00-summary.html`.
- **Diff** tab: pick any two recorded runs; invokes
  `diff-diagnostics.ps1` and shows the result inline.
- **Trends** tab: ScottPlot line chart of OK/WARN/FAIL counts over
  the last 20 runs; top 15 recurring WARN/FAIL verdicts across all
  history.
- **Plugins** tab: enumerates `diagnostics/plugins/`; import,
  enable/disable (renames `.ps1 <-> .ps1.disabled`), delete, open
  folder, reload.
- **Settings** tab: weekly scheduled run via `schtasks.exe`; update
  check against the GitHub releases API; background update probe
  on startup.
- Optional code-signing during `build.bat` via `SIGNING_PFX` env
  var (kills the SmartScreen "Windows protected your PC" dialog
  on family machines).

### diagnostics/

First public release of the generic Windows diagnostic toolset.

**Core**
- `system-diagnostics.ps1` — single-command Windows collector with 10
  sections covering system info, Python state, project files + git,
  installed updates, event logs (incl. bug-checks and app crashes),
  reliability records, WER + LiveKernelReports + minidumps + MEMORY.DMP,
  drivers + storage + SMART + memory + battery, processes + services +
  startup + scheduled tasks + HID devices, network (adapters, TCP,
  DNS, WiFi, proxy, time skew, firewall, HTTP probes), DISM CheckHealth
  (admin), and `systeminfo`.
- Polished `00-summary.html` report: stats cards, color-coded verdict
  pills, sticky table-of-contents nav, two-column file index, footer,
  embedded CSS (no JS, no CDN).
- Hybrid library/standalone mode — dot-source for composition,
  invoke directly for a normal run.

**Likely fixes**
- `Get-LikelyFixes` matches summary verdicts against a rule table and
  emits plain-English remediation steps for common patterns: BSODs,
  app crashes, unhealthy disk, clock skew, missing Python, WindowsApps
  stub, WinINET proxy, DNS failures, DB cloud placeholder, DB integrity,
  DISM corruption, missing elevation.

**Trend tracking**
- Every run is recorded in `%USERPROFILE%\diagnostics-history.json`
  (last 100 entries). Each report's Trends section surfaces what's
  new vs. the previous run, what's been resolved, what's recurring
  in >=3 of the last 5 runs, and OK/WARN/FAIL counts over the last
  10 runs.
- `trends-diagnostics.ps1` — standalone history viewer with filtering
  by project and host.

**Other tools**
- `diff-diagnostics.ps1` — compare two report folders or zips and
  show what changed (verdicts, hotfixes, drivers, services, startup,
  event-log counts).
- `run-diagnostics.bat` — double-click launcher for non-technical
  users that downloads the latest collector, runs it, and offers to
  pre-fill an email via mailto:.
- `install.ps1` — copies system/diff/trends diagnostics to a folder
  on PATH (default `~\bin\`).

**Options and switches**
- `-Sanitize` — redact username, host name, USERPROFILE path, MAC
  addresses, and private IPs from every text file before zipping.
- `-IncludeMiniDumps` — bundle `C:\Windows\Minidump\*.dmp` (listing
  only without the flag).
- `-CaptureNetSeconds N` — `netsh trace` window for N seconds; bundles
  the `.etl`. Requires elevation.
- Crash-dump auto-analysis — if Windows Debugging Tools (`cdb.exe`)
  is installed, runs `!analyze -v` on recent minidumps and dumps the
  bug-check root cause as text.

**Plugins**
- New `plugins/` folder dot-sourced by `Invoke-SystemDiagnostics`
  after section 10. Each `.ps1` runs in-context and can call
  `Add-Summary`, `Save-Text`, `Write-Section`, etc. Disabled
  plugins (`.ps1.disabled`) are skipped.
- README + sample plugin shipped alongside.

**Encoding hardening**
- All `.ps1` files: UTF-8 BOM + CRLF, ASCII-only content. Sidesteps a
  PowerShell 5.1 parser bug where em-dashes in BOM-less files decode
  as stray quote characters under Windows-1252.
- `.gitattributes` marks `*.ps1` / `*.bat` / `*.cmd` as `binary` so
  the BOM + CRLF survive `git checkout` and raw GitHub downloads.

### media-inventory/

Media Inventory Scanner reaches feature parity with first stable.

**App**
- Tkinter desktop UI for cataloging CDs, books, and Blu-ray discs via
  USB barcode scanner (HID keyboard emulation).
- Four free lookup APIs: UPCItemDB, Google Books, Open Library,
  MusicBrainz. Results cached locally to avoid rate limits.
- SQLite storage with optional cover-art thumbnails (Pillow).
- Search, filter by category, CSV export, DB backup, View Log button.

**Configurable DB path**
- Resolved in order: `MEDIA_INVENTORY_DB` env var ->
  `~/.media_inventory_config.json` -> default `~/media_inventory.db`.
- `setup.ps1 -UseOneDrive` auto-detects `$env:OneDrive` and writes the
  config to point the DB at OneDrive for cross-device sync.
- `setup.ps1 -DbPath` for an arbitrary location (Dropbox, USB, etc.).
- Existing DB at default location is migrated automatically when a
  new path is configured.

**Logging**
- `applog.py` wires Python `logging` to a rotating file handler at
  `<db_dir>/media_inventory.log` (2 MB x 5 rotations). Lives next to
  the DB so cloud sync covers it too.
- INFO by default, DEBUG when `MEDIA_INVENTORY_DEBUG=1` or when
  `run.bat --debug` is used.
- Activity log calls in `database.py` (adds/updates/deletes), `lookup.py`
  (per-API attempts with timings, cache hits, exceptions), and `main.py`
  (app start, scans, backups, exports).
- Tk callback exceptions and `sys.excepthook` route to the same log.

**App diagnostics**
- `app-diagnostics.ps1` — Media-Inventory-specific wrapper that
  dot-sources `../diagnostics/system-diagnostics.ps1`, adds three
  sections (DB resolution + integrity + row counts, app log capture
  with rotated backups, end-to-end lookup pipeline test against a
  known-good UPC), and forwards `-Sanitize`, `-IncludeMiniDumps`,
  and `-CaptureNetSeconds` to the system collector.

**Bootstrap**
- `setup.ps1` installs Python and Git via winget (with direct
  python.org / git-scm.com installers as fallback), clones the repo,
  installs `requirements.txt`, optionally restores a DB backup, and
  configures the DB location.

### Repository

- Split into `diagnostics/` and `media-inventory/` subfolders.
- Top-level `README.md` is a one-page repo overview.
- `LICENSE` (MIT) and this `CHANGELOG.md` added at the root.
- `DIAGNOSTICS.md` (diagnostic-tool landing page) and
  `INSTRUCTIONS-FOR-USERS.md` (non-technical user guide) live under
  `diagnostics/`.

[1.0.0]: https://github.com/paulhale70/System-tools/releases/tag/v1.0.0
