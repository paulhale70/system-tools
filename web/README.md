# System-tools Web Dashboard (v3-web branch)

A standalone, interactive web dashboard for browsing your diagnostics
history. **One file, no build step, no server, no install.** Open it
in any modern browser, drag-and-drop your `diagnostics-history.json`,
and explore.

This sits alongside the WPF desktop (v1) and the PowerShell scripts.
It does *not* run new diagnostics — it visualizes the JSON history
that `system-diagnostics.ps1` already maintains at
`%USERPROFILE%\diagnostics-history.json`.

## How to use

1. Open `web/index.html` in any modern browser (Edge, Chrome, Firefox).
2. Drag-and-drop your `diagnostics-history.json` onto the page,
   or click "Choose file".
3. Tabs:
   - **Overview** — totals, hosts, projects, latest run.
   - **History** — searchable / filterable list of every run; click
     one to see its full verdict list.
   - **Trends** — OK / WARN / FAIL line chart over the last 20 runs.
   - **Recurring** — verdicts that appear most often across all runs.

The loaded JSON is cached in browser `localStorage` so a refresh
keeps your data.

## Why a single static file?

- **Zero install** for the audience: open one HTML in a browser.
- **Zero server**: no Node, no Python, no Docker.
- **Easy to share**: email the `.html`, paste into a OneDrive, drop in
  a USB stick. Anyone with a browser can use it.
- **Easy to read**: every line of behavior is in one file, no build
  pipeline. View source to audit.

The trade-off vs. the WPF desktop:

| | WPF desktop (`desktop/`) | Web dashboard (`web/`) |
| --- | --- | --- |
| Runs new diagnostics | Yes | No - viewer only |
| Plugin management | Yes | No |
| Scheduled runs | Yes | No |
| Update checker | Yes | No |
| Install required | One 75 MB `.exe` | Just a browser |
| Cross-platform | Windows only | Anywhere |

Use the desktop when you want to *do* things. Use the web dashboard
when you want to *understand* the history at a glance, share findings,
or look at a report from a non-Windows machine.

## Tech stack

- **Tailwind CSS** via CDN for styling
- **Alpine.js** for reactivity (a tiny declarative framework, no build)
- **Chart.js** for the trends line chart

All three load from `jsDelivr` CDN. With a network connection the page
is self-contained; without one it falls back gracefully (Alpine and
Chart.js won't initialize, but you can still open it later).

## Roadmap

This is v3 v0.1. Possible follow-ups (no order assumed):

- Inline iframe of the selected run's `00-summary.html` (requires
  drag-dropping the report folder too).
- Multi-file load: drop several JSON files to compare hosts.
- Export the dashboard view as PDF / image for sharing.
- Optional small-Python local server (`web/server.py`) to run
  diagnostics on demand from the browser. Adds a runtime requirement.
- PWA install so the file becomes a real desktop "app".
- Embedded "share to GitHub gist" button.

## Branch policy

Lives on the `v3-web` branch. To merge into `main`, the WPF desktop
and the web dashboard both ship side by side - they are non-overlapping
deliverables. Suggested approach: open a PR from `v3-web` -> `main`
once the dashboard has a feature set worth releasing as part of v1.1.
