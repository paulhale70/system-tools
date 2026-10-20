# System-tools Web Dashboard

An interactive dashboard for browsing your diagnostics history. It is
**one HTML file** used in two ways:

- **Inside the desktop app** - the **Dashboard** tab of
  `SystemTools.Desktop.exe`. The app serves this file from inside the
  `.exe` and pushes the history in automatically, so there is nothing
  to load and it works offline.
- **Standalone in a browser** - open `web/index.html` in any modern
  browser and drag-and-drop your `diagnostics-history.json`. Useful on
  a non-Windows machine or for sharing findings.

It does *not* run new diagnostics. It visualizes the JSON history that
`system-diagnostics.ps1` maintains at
`%USERPROFILE%\diagnostics-history.json`.

## Tabs

- **Overview** - totals, hosts, projects, latest run.
- **History** - searchable / filterable list of every run; click one
  to see its full verdict list.
- **Trends** - OK / WARN / FAIL line chart over the last 20 runs.
- **Recurring** - verdicts that appear most often across all runs.

## Standalone use

1. Open `web/index.html` in Edge, Chrome or Firefox.
2. Drag-and-drop `diagnostics-history.json` onto the page, or click
   "Choose file".

The loaded JSON is cached in browser `localStorage` so a refresh keeps
your data. Standalone mode needs a network connection, because the
libraries load from CDNs.

## Embedded mode (desktop app)

When the page finds `window.chrome.webview` (WebView2), it:

- hides its own header and the file-picking UI,
- posts `{ type: 'ready' }` to the host,
- renders whatever the host sends as
  `{ type: 'history', source, runs: [...] }` (re-sent after every run
  and whenever the tab is opened).

See `desktop/Views/DashboardView.xaml.cs` for the host side.

## Tech stack

- **Tailwind CSS** 3.4.16 (Play CDN build) for styling
- **Alpine.js** 3.13.5 for reactivity (no build step)
- **Chart.js** 4.4.1 for the trends chart

`index.html` references these at pinned CDN URLs. Identical copies live
in `vendor/`; the desktop app compiles them in and answers those CDN
requests from them, which is what makes the Dashboard tab work offline.
**When bumping a library, change the URL in `index.html`, the file in
`vendor/` and the map in `DashboardView.xaml.cs` together.**

| File | Source |
| --- | --- |
| `vendor/tailwindcss-3.4.16.js` | https://cdn.tailwindcss.com/3.4.16 |
| `vendor/alpinejs-3.13.5.min.js` | https://cdn.jsdelivr.net/npm/alpinejs@3.13.5/dist/cdn.min.js |
| `vendor/chartjs-4.4.1.umd.min.js` | https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js |

All three are MIT licensed.

## Roadmap

Possible follow-ups (no order assumed):

- Inline view of the selected run's `00-summary.html` (in the app this
  is already on the Run tab).
- Multi-file load: drop several JSON files to compare hosts.
- Export the dashboard view as PDF / image for sharing.
