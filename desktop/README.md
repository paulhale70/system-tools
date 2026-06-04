# System-tools Desktop

The v2 GUI front-end for the diagnostics toolset. WPF / .NET 8.
Wraps the existing `system-diagnostics.ps1` collector — the GUI runs
the script, surfaces progress, and renders the resulting HTML report
in an embedded WebView2 control.

## Status

**v1.0.0 scaffold.** Working shell:
- Run button with toggles for `-Sanitize`, `-IncludeMiniDumps`,
  and `-CaptureNetSeconds`
- History sidebar populated from `%USERPROFILE%\diagnostics-history.json`
  (newest first, with OK/WARN/FAIL count pills per run)
- Embedded WebView2 viewer for `00-summary.html`
- Status bar tail of the script's live output

Roadmap items (not yet wired): in-app diff view, trends dashboard
with charts, scheduled runs, plugin browser, settings, code signing,
auto-update.

## Build requirements

- Windows 10 / 11
- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- [WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/)
  (already present on every Win10/11 box that has Edge)

## Building

```powershell
cd desktop
.\build.bat
```

This produces a self-contained single-file `.exe` at:
```
bin\Release\net8.0-windows\win-x64\publish\SystemTools.Desktop.exe
```

The build embeds the .NET 8 runtime, so the `.exe` runs on any Win10/11
machine without a separate `.NET` install. Expect ~75 MB.

## Distribution layout

The runner finds `system-diagnostics.ps1` in this order:
1. `<exe-dir>\diagnostics\system-diagnostics.ps1`  *(recommended)*
2. The repo dev layout (used when running from `bin\Debug\...`)
3. `%USERPROFILE%\bin\system-diagnostics.ps1` (installed via `diagnostics\install.ps1`)

For a family-distributable bundle:

```
SystemTools-1.0/
├── SystemTools.Desktop.exe
└── diagnostics/
    ├── system-diagnostics.ps1
    ├── diff-diagnostics.ps1
    └── trends-diagnostics.ps1
```

Zip that folder and send. The user unzips and double-clicks the `.exe`.

## Architecture

```
MainWindow.xaml          Layout: header, toolbar, history list,
                         WebView2 report viewer, status bar.
ViewModels/MainViewModel Run state, options, history collection,
                         selected-report logic, INPC.
Services/HistoryReader   Loads diagnostics-history.json.
Services/DiagnosticsRunner Spawns powershell.exe and streams stdout.
Models/RunHistoryEntry   Matches the JSON shape written by
                         Save-RunHistory in system-diagnostics.ps1.
```

The GUI never reimplements collection logic. Every change to what
gets captured stays in `system-diagnostics.ps1`; the GUI inherits
it for free.

## Code signing (TODO)

Without a code-signing certificate, SmartScreen will warn on first
launch from a downloaded zip. Two paths:

1. **Cheap fix**: tell users to right-click `.exe` -> Properties ->
   Unblock. Same step that's already in the `run-diagnostics.bat`
   instructions for non-tech users.
2. **Proper fix**: buy an OV or EV code-signing cert (~$80-200/yr) and
   sign during publish (`signtool sign`). Adds to the build pipeline
   but eliminates the SmartScreen dialog.

For v1.0.0 we ship unsigned; signing is queued for v1.1.
