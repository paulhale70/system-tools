# System-tools Desktop

WPF / .NET 8 app for the diagnostic toolset, and the one tool that
brings the repo's three diagnostics pieces together. It wraps the
`system-diagnostics.ps1` collector, hosts the web dashboard as a tab,
and adds in-app diff, plugin management, scheduled runs, and update
checking. The scripts and the dashboard are compiled into a
self-contained single-file `.exe`, so non-technical users only need to
double-click.

## Features

| Tab | What it does |
| --- | --- |
| **Run** | Run button + `-Sanitize` / `-IncludeMiniDumps` / `-CaptureNetSeconds` toggles. History sidebar (newest first, OK/WARN/FAIL count pills). Embedded WebView2 renders the selected `00-summary.html`. |
| **Diff** | Pick any two recorded runs and compare them. Invokes `diff-diagnostics.ps1` in the background and shows the resulting text inline. |
| **Dashboard** | `web/index.html` (Overview / History / Trends / Recurring), served from inside the `.exe` with its libraries, so it works offline. The history is pushed in automatically and refreshed after each run. |
| **Plugins** | List of `.ps1` files in `diagnostics/plugins/`. Import a new plugin, enable / disable (rename `.ps1 <-> .ps1.disabled`), delete, open the folder, reload. Active plugins are dot-sourced by `system-diagnostics.ps1` after section 10. |
| **Settings** | Weekly scheduled run via `schtasks.exe` (day + time + sanitize toggle). Update check against the GitHub releases API with one-click jump to the release page. Current/latest version. |

The GUI checks for newer releases automatically in the background on
startup; if one is available the Settings tab surfaces it.

## Build requirements

- Windows 10 / 11
- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- [WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/)
  (already present on every Win10/11 box with Edge)

NuGet dependencies pulled at build time:
- `Microsoft.Web.WebView2` (report viewer and Dashboard tab)

Compiled in as embedded resources (see the csproj):
- `../diagnostics/*.ps1` (except `install.ps1`) and the sample plugin
- `../web/index.html` and `../web/vendor/*.js`

## Building

```powershell
cd desktop
.\build.bat
```

Output:
```
desktop\bin\Release\net8.0-windows\win-x64\publish\SystemTools.Desktop.exe
```

About 72 MB (includes the .NET 8 runtime). Runs on any Win10/11
machine with no .NET install required.

### Optional code-signing

To eliminate the SmartScreen "Windows protected your PC" dialog on
family machines, sign the `.exe` with an OV/EV code-signing cert
(~$80-200/yr from SSL.com, Certum, etc.). The build script signs
automatically when `SIGNING_PFX` is set:

```powershell
$env:SIGNING_PFX = "C:\certs\code.pfx"
$env:SIGNING_PFX_PWD = "hunter2"
.\build.bat
```

Requires `signtool.exe` on PATH (ships with the Windows SDK).

## Distribution

The `.exe` is the whole distribution: send it, double-click it. On
first run (and after an upgrade) it unpacks its scripts to
`%LOCALAPPDATA%\SystemTools\diagnostics\`. The core scripts there are
replaced whenever they differ from the ones in the `.exe`; the
`plugins\` folder is only seeded the first time and then belongs to
the user.

The GUI resolves `system-diagnostics.ps1` in this order:

1. `diagnostics\system-diagnostics.ps1` next to the `.exe` or in a
   parent folder - a hand-edited distribution, or the repo itself when
   running from `desktop\bin\...`
2. The bundled copy in `%LOCALAPPDATA%\SystemTools\diagnostics\`
   (always available)

## Architecture

```
MainWindow.xaml          Sidebar nav + status bar. Swaps a UserControl
                         into the content slot based on SelectedTab.
ViewModels/
  MainViewModel          Root: navigation state, history list, run
                         action; owns the sub-view-models.
  DiffViewModel          Picks two runs; calls DiffService.
  PluginsViewModel       Wraps PluginManager (list / enable / disable
                         / delete / import).
  SettingsViewModel      Schedule editor + update checker.
Views/
  RunView                Toolbar, history sidebar, WebView2 report.
  DiffView               Two run pickers + Compare button + diff text.
  DashboardView          WebView2 hosting web/index.html; serves it
                         and its vendored libraries from embedded
                         resources and posts the history to it.
  PluginsView            DataGrid of plugins + action buttons.
  SettingsView           Schedule form + update card.
Services/
  BundledAssets          Unpacks the embedded scripts; opens embedded
                         web files.
  DiagnosticsRunner      Spawns powershell.exe with system-diagnostics.ps1.
  HistoryReader          Loads diagnostics-history.json.
  DiffService            Invokes diff-diagnostics.ps1.
  PluginManager          Enumerates diagnostics/plugins/.
  ScheduledTaskService   Wraps schtasks.exe for register/remove/query.
  UpdateChecker          GET github releases API; semver compare.
Models/
  RunHistoryEntry        JSON shape from Save-RunHistory.
```

The GUI never reimplements collection logic. Every change to what
gets captured stays in `system-diagnostics.ps1`; the GUI inherits it
for free.

## Status

**v1.4.0** - one tool: scripts and the web dashboard compiled into the
`.exe`; the Dashboard tab replaces the ScottPlot Trends tab.

**v1.0.0** - shipping all six v2 roadmap items folded into v1:
- In-app diff view
- Trends dashboard with real charts
- Scheduled runs (via Settings)
- Plugin browser (with PS-side dot-source contract)
- Update check (via Settings + background on startup)
- Code-signing pipeline hook (set `SIGNING_PFX` env var)
