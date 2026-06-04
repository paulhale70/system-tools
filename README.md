# System-tools

Version **1.0.0** &middot;
[CHANGELOG](CHANGELOG.md) &middot;
[LICENSE](LICENSE) (MIT)

Three sibling projects in one repo:

| Folder | What it is |
| --- | --- |
| [`diagnostics/`](diagnostics/) | Generic Windows diagnostic toolset. PowerShell scripts that collect system state into a styled HTML report with trend tracking, plain-English fix suggestions, and a comparison tool for two runs. Project-agnostic - works for any project on any Windows machine. |
| [`desktop/`](desktop/) | WPF / .NET 8 GUI front-end (v2 in progress). Wraps `diagnostics/system-diagnostics.ps1` with a Run button, history sidebar, and embedded HTML report viewer. Distributable as a self-contained single-file `.exe`. |
| [`media-inventory/`](media-inventory/) | Media Inventory Scanner. A Python/Tkinter desktop app for cataloging CDs, books, and Blu-rays using a USB barcode scanner. Uses free public APIs for lookups. |

## Quick links

- Diagnostics: [`diagnostics/DIAGNOSTICS.md`](diagnostics/DIAGNOSTICS.md)
- Diagnostics for non-technical users:
  [`diagnostics/INSTRUCTIONS-FOR-USERS.md`](diagnostics/INSTRUCTIONS-FOR-USERS.md)
- Desktop GUI: [`desktop/README.md`](desktop/README.md)
- Media Inventory Scanner: [`media-inventory/README.md`](media-inventory/README.md)
