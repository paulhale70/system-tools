# System-tools Desktop

WPF / .NET 8 GUI front-end for the diagnostic toolset. The GUI wraps
the existing `system-diagnostics.ps1` collector and adds in-app diff,
trend charts, plugin management, scheduled runs, and update checking.
Distributes as a self-contained single-file `.exe` so non-technical
users only need to double-click.

## Features

| Tab | What it does |
| --- | --- |
| **Run** | Run button + `-Sanitize` / `-IncludeMiniDumps` / `-CaptureNetSeconds` toggles. History sidebar (newest first, OK/WARN/FAIL count pills). Embedded WebView2 renders the selected `00-summary.html`. |
| **Diff** | Pick any two recorded runs and compare them. Invokes `diff-diagnostics.ps1` in the background and shows the resulting text inline. |
| **Trends** | OK / WARN / FAIL counts over the last 20 runs as a real line chart (ScottPlot). Top 15 recurring WARN/FAIL verdicts across all history. |
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
- `Microsoft.Web.WebView2` (embedded HTML report viewer)
- `ScottPlot.WPF` (trend chart)

## Building

```powershell
cd desktop
.\build.bat
```

Output:
```
desktop\bin\Release\net8.0-windows\win-x64\publish\SystemTools.Desktop.exe
```

About 75 MB (includes .NET 8 runtime + ScottPlot). Runs on any
Win10/11 machine with no .NET install required.

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

## Distribution layout

```
SystemTools/
├── SystemTools.Desktop.exe       (~75 MB, no install needed)
└── diagnostics/
    ├── system-diagnostics.ps1
    ├── diff-diagnostics.ps1
    ├── trends-diagnostics.ps1
    └── plugins/
        ├── README.md
        └── _sample.ps1.disabled
```

Zip → send → unzip → double-click. The GUI resolves
`system-diagnostics.ps1` in this order:

1. `<exe-dir>\diagnostics\system-diagnostics.ps1` *(recommended distribution layout)*
2. The repo dev layout (`bin\Debug\...` -> repo root -> `diagnostics\`)
3. `%USERPROFILE%\bin\system-diagnostics.ps1` (installed via `diagnostics\install.ps1`)

## Architecture

```
MainWindow.xaml          Sidebar nav + status bar. Swaps a UserControl
                         into the content slot based on SelectedTab.
ViewModels/
  MainViewModel          Root: navigation state, history list, run
                         action; owns the sub-view-models.
  DiffViewModel          Picks two runs; calls DiffService.
  TrendsViewModel        Builds chart series + recurring tally.
  PluginsViewModel       Wraps PluginManager (list / enable / disable
                         / delete / import).
  SettingsViewModel      Schedule editor + update checker.
Views/
  RunView                Toolbar, history sidebar, WebView2 report.
  DiffView               Two run pickers + Compare button + diff text.
  TrendsView             ScottPlot line chart + DataGrid for recurring.
  PluginsView            DataGrid of plugins + action buttons.
  SettingsView           Schedule form + update card.
Services/
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

**v1.0.0** - shipping all six v2 roadmap items folded into v1:
- In-app diff view
- Trends dashboard with real charts
- Scheduled runs (via Settings)
- Plugin browser (with PS-side dot-source contract)
- Update check (via Settings + background on startup)
- Code-signing pipeline hook (set `SIGNING_PFX` env var)
