# Media Inventory Scanner

A desktop app for cataloging physical media using a USB barcode scanner.
Supports **CDs**, **Books**, and **Blu-ray** discs. Scanned items are looked up
automatically via free public APIs — no API keys required.

---

## Requirements

| Requirement | Notes |
|---|---|
| Windows 10 / 11 | (also works on macOS and Linux) |
| Python 3.9 or later | https://python.org/downloads |
| USB barcode scanner | Any USB HID scanner (keyboard-emulation mode) |
| Internet connection | For barcode lookups |

Tested with the **WoneNice USB Laser Barcode Scanner** and compatible models.

---

## Installation

### 1 — Install Python

Download and install Python 3.9+ from https://python.org/downloads.

During installation on Windows, check **"Add Python to PATH"**.

Verify it worked by opening a Command Prompt and running:

```
python --version
```

You should see something like `Python 3.11.x`.

---

### 2 — Download the app

**Option A — Git clone**

```
git clone https://github.com/paulhale70/System-tools.git
cd System-tools\media-inventory
```

**Option B — Download ZIP**

1. Go to https://github.com/paulhale70/System-tools
2. Click **Code → Download ZIP**
3. Extract the ZIP to a folder of your choice

---

### 3 — Install dependencies

Open a Command Prompt inside the project folder and run:

```
pip install -r requirements.txt
```

This installs:

| Package | Purpose |
|---|---|
| `requests` | API calls for barcode lookup |
| `Pillow` | Cover art / thumbnail display (optional) |

If `pip` is not found, try `python -m pip install -r requirements.txt`.

---

### 4 — Run the app

**Double-click `run.bat`** — this installs/updates dependencies automatically
and then launches the app.

Or run manually from a Command Prompt:

```
python main.py
```

---

## Using the app

### Scanning items

1. Plug in your USB barcode scanner — no drivers needed, it's plug-and-play.
2. Launch the app. The **Scan / Enter UPC** field is focused automatically.
3. Point the scanner at a barcode and pull the trigger.
4. The scanner types the barcode and presses Enter automatically.
5. The app queries several free databases and fills in the details.
6. Adjust **Condition** or **Quantity** if needed, then click **Add to Inventory**.

The scan field refocuses immediately after each item is added, so you can
scan the next item without touching the keyboard or mouse.

### Manual entry

If an item has no barcode or isn't found online, click **Manual Entry**,
fill in the fields, and click **Add to Inventory**.

### Keyboard shortcuts

| Key | Action |
|---|---|
| `Enter` | Look up the barcode in the scan field |
| `Escape` | Clear the scan field and return focus to it |
| `Ctrl + F` | Focus the search box |

---

## Barcode lookup sources

The app tries the following free APIs in order until it finds a match:

| Source | Best for | Free limit |
|---|---|---|
| UPC Item DB | All product types | 100 lookups / day |
| Google Books | Books by ISBN | 1,000 / day per IP |
| Open Library | Books (fallback) | Unlimited |
| MusicBrainz | CDs and music | 1 request / second |

If a barcode isn't found, the fields are left blank for manual entry.

---

## Inventory management

| Action | How |
|---|---|
| **Edit an item** | Click its row in the table, update fields, click **Save Changes** |
| **Delete an item** | Click its row, click **Delete**, confirm |
| **Filter by category** | Use the **Show: All / CD / Book / Blu-ray** radio buttons |
| **Search** | Type in the search box (searches title, artist/author, UPC) |
| **Export to CSV** | Click **Export CSV** in the top-right corner |

---

## Database

Item data is stored in a local SQLite database file:

```
C:\Users\<your-username>\media_inventory.db
```

The file is created automatically on first run. You can open it with any
SQLite viewer (e.g. [DB Browser for SQLite](https://sqlitebrowser.org/)).

---

## Troubleshooting

**"python is not recognized"**
Python was not added to PATH during installation. Re-run the Python installer
and check the "Add Python to PATH" option, or set the PATH variable manually.

**"ModuleNotFoundError: No module named 'requests'"**
Run `pip install -r requirements.txt` from the project folder.

**Barcode not found**
- UPC Item DB allows 100 free lookups per day — you may have hit the limit.
- Try again the next day, or enter the item manually.
- Older or regional releases may not be in any free database.

**Cover art not showing**
Install Pillow: `pip install Pillow`

**Scanner input goes to the wrong field**
Press `Escape` to clear and refocus the scan field before scanning.
