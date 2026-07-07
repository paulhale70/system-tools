# System-tools

Version **1.3.0** &middot;
[CHANGELOG](CHANGELOG.md) &middot;
[LICENSE](LICENSE) (MIT)

Four sibling projects in one repo:

| Folder | What it is |
| --- | --- |
| [`diagnostics/`](diagnostics/) | Generic Windows diagnostic toolset. PowerShell scripts that collect system state into a styled HTML report with trend tracking, plain-English fix suggestions, and a comparison tool for two runs. Project-agnostic - works for any project on any Windows machine. |
| [`desktop/`](desktop/) | WPF / .NET 8 GUI front-end. Wraps `diagnostics/system-diagnostics.ps1` with run controls, history sidebar, in-app diff, trend charts (ScottPlot), plugin browser, scheduled runs, and update checker. Distributable as a self-contained single-file `.exe`. |
| [`web/`](web/) | Single-file HTML SPA dashboard. Drag-drop your `diagnostics-history.json` into any browser to explore Overview / History / Trends / Recurring tabs. No install, no server, no build - one file, any OS. |
| [`media-inventory/`](media-inventory/) | Media Inventory Scanner. A Python/Tkinter desktop app for cataloging CDs, books, and Blu-rays using a USB barcode scanner. Uses free public APIs for lookups. |

## When to use which

- **Run** new diagnostics: `desktop/` (GUI) or `diagnostics/run-diagnostics.bat` (one-shot)
- **View** past runs across machines, share findings: `web/index.html`
- **Compare** two runs on the same machine: `desktop/` Diff tab or `diagnostics/diff-diagnostics.ps1`
- **Bootstrap** a fresh Windows install for the inventory app: `media-inventory/setup.ps1`
- **Help non-technical family**: email them `diagnostics/run-diagnostics.bat`

## Quick links

- Diagnostics: [`diagnostics/DIAGNOSTICS.md`](diagnostics/DIAGNOSTICS.md)
- Diagnostics for non-technical users:
  [`diagnostics/INSTRUCTIONS-FOR-USERS.md`](diagnostics/INSTRUCTIONS-FOR-USERS.md)
- Desktop GUI: [`desktop/README.md`](desktop/README.md)
- Web dashboard: [`web/README.md`](web/README.md)
- Media Inventory Scanner: [`media-inventory/README.md`](media-inventory/README.md)
