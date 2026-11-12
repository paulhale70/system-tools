# System-tools

Version **1.4.1** &middot;
[CHANGELOG](CHANGELOG.md) &middot;
[LICENSE](LICENSE) (MIT)

**System-tools Diagnostics** is one Windows app, `SystemTools.Desktop.exe`,
built from the first three folders below. The PowerShell collector and
the web dashboard are compiled into the `.exe`, so it is a single file
to hand out: Run, Dashboard, Diff, Plugins and Settings in one window.

The Media Inventory Scanner used to live here in `media-inventory/`. It
is a separate app, so it now has its own repository:
[paulhale70/media-inventory](https://github.com/paulhale70/media-inventory).

| Folder | What it is |
| --- | --- |
| [`desktop/`](desktop/) | **The app.** WPF / .NET 8 GUI with run controls, history and report viewer, the dashboard, in-app diff, plugin browser, scheduled runs and update checker. Publishes as one self-contained `.exe`. |
| [`diagnostics/`](diagnostics/) | The engine. PowerShell scripts that collect system state into a styled HTML report with trend tracking, plain-English fix suggestions, and a comparison tool for two runs. Bundled into the app; also usable on their own (e.g. the emailable `run-diagnostics.bat`). |
| [`web/`](web/) | The dashboard (Overview / History / Trends / Recurring). One HTML file: it is the app's **Dashboard** tab, and still works standalone in any browser via drag-and-drop. |

## When to use which

- **Run, view and compare** diagnostics: the app (`desktop/`)
- **One-shot run without installing anything**: `diagnostics/run-diagnostics.bat`
- **View history on a machine without the app** (or a non-Windows one): open `web/index.html` in a browser
- **Compare** two runs from a script: `diagnostics/diff-diagnostics.ps1`
- **Help non-technical family**: email them `diagnostics/run-diagnostics.bat`

## Quick links

- Diagnostics: [`diagnostics/DIAGNOSTICS.md`](diagnostics/DIAGNOSTICS.md)
- Diagnostics for non-technical users:
  [`diagnostics/INSTRUCTIONS-FOR-USERS.md`](diagnostics/INSTRUCTIONS-FOR-USERS.md)
- Desktop GUI: [`desktop/README.md`](desktop/README.md)
- Web dashboard: [`web/README.md`](web/README.md)

## Layout

```
SystemTools.sln         Visual Studio / dotnet solution (opens desktop/)
desktop/                WPF app: Views/, ViewModels/, Services/, Models/
diagnostics/            PowerShell engine + plugins/  (path is fixed: see below)
web/                    Dashboard: index.html + vendor/ (pinned JS libs)
```

`diagnostics/system-diagnostics.ps1` must not move or be renamed:
copies of `run-diagnostics.bat` already emailed out download it from
that path on `main`.

Build the app from the root with `dotnet build SystemTools.sln`, or run
`desktop\build.bat` for the signed single-file release `.exe`.
