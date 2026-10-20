# System-tools

Version **1.4.0** &middot;
[CHANGELOG](CHANGELOG.md) &middot;
[LICENSE](LICENSE) (MIT)

**System-tools Diagnostics** is one Windows app, `SystemTools.Desktop.exe`,
built from the first three folders below. The PowerShell collector and
the web dashboard are compiled into the `.exe`, so it is a single file
to hand out: Run, Dashboard, Diff, Plugins and Settings in one window.
The media inventory app is a separate project that shares the repo.

| Folder | What it is |
| --- | --- |
| [`desktop/`](desktop/) | **The app.** WPF / .NET 8 GUI with run controls, history and report viewer, the dashboard, in-app diff, plugin browser, scheduled runs and update checker. Publishes as one self-contained `.exe`. |
| [`diagnostics/`](diagnostics/) | The engine. PowerShell scripts that collect system state into a styled HTML report with trend tracking, plain-English fix suggestions, and a comparison tool for two runs. Bundled into the app; also usable on their own (e.g. the emailable `run-diagnostics.bat`). |
| [`web/`](web/) | The dashboard (Overview / History / Trends / Recurring). One HTML file: it is the app's **Dashboard** tab, and still works standalone in any browser via drag-and-drop. |
| [`media-inventory/`](media-inventory/) | Media Inventory Scanner. A Python/Tkinter desktop app for cataloging CDs, books, and Blu-rays using a USB barcode scanner. Uses free public APIs for lookups. |

## When to use which

- **Run, view and compare** diagnostics: the app (`desktop/`)
- **One-shot run without installing anything**: `diagnostics/run-diagnostics.bat`
- **View history on a machine without the app** (or a non-Windows one): open `web/index.html` in a browser
- **Compare** two runs from a script: `diagnostics/diff-diagnostics.ps1`
- **Bootstrap** a fresh Windows install for the inventory app: `media-inventory/setup.ps1`
- **Help non-technical family**: email them `diagnostics/run-diagnostics.bat`

## Quick links

- Diagnostics: [`diagnostics/DIAGNOSTICS.md`](diagnostics/DIAGNOSTICS.md)
- Diagnostics for non-technical users:
  [`diagnostics/INSTRUCTIONS-FOR-USERS.md`](diagnostics/INSTRUCTIONS-FOR-USERS.md)
- Desktop GUI: [`desktop/README.md`](desktop/README.md)
- Web dashboard: [`web/README.md`](web/README.md)
- Media Inventory Scanner: [`media-inventory/README.md`](media-inventory/README.md)
