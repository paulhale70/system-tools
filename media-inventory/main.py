from __future__ import annotations

"""
Media Inventory Scanner
=======================
Scan UPC/ISBN barcodes to catalog CDs, Books, and Blu-ray media.
USB barcode scanners work as keyboard emulators — they type the
barcode number and press Enter, so keep focus on the scan field.
"""

import tkinter as tk
from tkinter import ttk, messagebox, filedialog
import threading
import csv
import io
import logging
import os
import shutil
import subprocess
import sys
from datetime import datetime

import applog
applog.setup_logging()

import database
import lookup

log = logging.getLogger('app')

# ── Try optional deps ──────────────────────────────────────────────────────────
try:
    from PIL import Image, ImageTk
    import requests as _req
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False

try:
    import requests  # noqa: F401  (used in lookup.py; check here for warning)
    REQUESTS_AVAILABLE = True
except ImportError:
    REQUESTS_AVAILABLE = False

# ── Palette ────────────────────────────────────────────────────────────────────
BG         = "#1a1b2e"
PANEL      = "#252640"
INPUT_BG   = "#13132a"
ACCENT     = "#6c63ff"
SUCCESS    = "#4ade80"
WARNING    = "#fbbf24"
DANGER     = "#f87171"
TEXT       = "#e2e8f0"
SUBTEXT    = "#94a3b8"
BORDER     = "#3a3b5c"

CATEGORIES = ["CD", "Book", "Blu-ray"]
CONDITIONS = ["Sealed", "Mint", "Very Good", "Good", "Fair", "Poor"]
GENRES = {
    "CD":      ["", "Album", "Single", "EP", "Compilation", "Soundtrack", "Classical"],
    "Book":    ["", "Fiction", "Non-fiction", "Graphic Novel", "Reference", "Children's"],
    "Blu-ray": ["", "Standard", "4K UHD", "Box Set", "Anime", "Documentary"],
}

CAT_COLORS = {
    "CD":      "#1d3557",
    "Book":    "#1b3a2d",
    "Blu-ray": "#2d1b45",
}


# ──────────────────────────────────────────────────────────────────────────────
class App(tk.Tk):
    def __init__(self):
        super().__init__()
        applog.install_tk_excepthook(self)
        log.info('App starting (db=%s)', database.DB_PATH)
        database.init_db()

        self.title("Media Inventory Scanner")
        self.geometry("1280x760")
        self.minsize(960, 620)
        self.configure(bg=BG)

        # State
        self.current_scan: dict | None = None
        self.selected_id: int | None = None
        self.filter_var  = tk.StringVar(value="All")
        self.search_var  = tk.StringVar()
        self.search_var.trace_add('write', lambda *_: self._refresh_table())

        self._setup_styles()
        self._build_ui()
        self._refresh_table()
        self._update_stats()

        # Keyboard shortcuts
        self.bind_all('<Escape>', lambda _: self._focus_scan())
        self.bind('<Control-f>', lambda _: self.search_entry.focus_set())

        self.scan_entry.focus_set()

        if not REQUESTS_AVAILABLE:
            messagebox.showwarning(
                "Missing dependency",
                "The 'requests' package is not installed.\n"
                "Run:  pip install -r requirements.txt\n\n"
                "Barcode lookup will not work until it is installed."
            )

    # ── Styles ─────────────────────────────────────────────────────────────────

    def _setup_styles(self):
        s = ttk.Style(self)
        s.theme_use('clam')

        s.configure("Treeview",
            background=PANEL, foreground=TEXT,
            fieldbackground=PANEL, borderwidth=0,
            rowheight=28, font=('Segoe UI', 10)
        )
        s.configure("Treeview.Heading",
            background=BG, foreground=SUBTEXT,
            borderwidth=0, font=('Segoe UI', 9, 'bold')
        )
        s.map("Treeview",
            background=[('selected', ACCENT)],
            foreground=[('selected', '#ffffff')]
        )
        s.configure("Vertical.TScrollbar",
            background=PANEL, troughcolor=BG,
            bordercolor=PANEL, arrowcolor=SUBTEXT
        )
        s.configure("TCombobox",
            fieldbackground=INPUT_BG, background=INPUT_BG,
            foreground=TEXT, selectbackground=ACCENT
        )

    # ── UI construction ────────────────────────────────────────────────────────

    def _build_ui(self):
        self._build_header()
        self._build_scan_bar()
        content = tk.Frame(self, bg=BG)
        content.pack(fill='both', expand=True, padx=12, pady=(0, 8))
        self._build_detail_panel(content)
        self._build_inventory_panel(content)
        self._build_status_bar()

    def _build_header(self):
        bar = tk.Frame(self, bg=BG)
        bar.pack(fill='x', padx=12, pady=(10, 4))
        tk.Label(bar, text="📀  Media Inventory Scanner",
                 bg=BG, fg=TEXT, font=('Segoe UI', 16, 'bold')).pack(side='left')
        tk.Button(bar, text="Export CSV",
                  bg=PANEL, fg=SUBTEXT, relief='flat',
                  padx=10, pady=5, cursor='hand2',
                  command=self._export_csv).pack(side='right')
        tk.Button(bar, text="Backup DB",
                  bg=PANEL, fg=SUBTEXT, relief='flat',
                  padx=10, pady=5, cursor='hand2',
                  command=self._backup_db).pack(side='right', padx=(0, 6))
        tk.Button(bar, text="View Log",
                  bg=PANEL, fg=SUBTEXT, relief='flat',
                  padx=10, pady=5, cursor='hand2',
                  command=self._open_log).pack(side='right', padx=(0, 6))

    def _build_scan_bar(self):
        bar = tk.Frame(self, bg=PANEL)
        bar.pack(fill='x', padx=12, pady=(0, 8))

        inner = tk.Frame(bar, bg=PANEL)
        inner.pack(fill='x', padx=12, pady=10)

        tk.Label(inner, text="Scan / Enter UPC:",
                 bg=PANEL, fg=SUBTEXT,
                 font=('Segoe UI', 10)).pack(side='left', padx=(0, 8))

        self.scan_var = tk.StringVar()
        self.scan_entry = tk.Entry(
            inner, textvariable=self.scan_var,
            bg=INPUT_BG, fg=TEXT, insertbackground=TEXT,
            relief='flat', font=('Courier New', 13), width=22,
            highlightthickness=2, highlightcolor=ACCENT,
            highlightbackground=BORDER
        )
        self.scan_entry.pack(side='left', ipady=6, ipadx=6)
        self.scan_entry.bind('<Return>',   self._on_scan)
        self.scan_entry.bind('<KP_Enter>', self._on_scan)

        self.scan_btn = tk.Button(
            inner, text="Look Up", bg=ACCENT, fg='#ffffff',
            relief='flat', padx=14, pady=6,
            cursor='hand2', font=('Segoe UI', 10, 'bold'),
            command=self._on_scan
        )
        self.scan_btn.pack(side='left', padx=(6, 0))

        tk.Button(
            inner, text="Manual Entry", bg=PANEL, fg=SUBTEXT,
            relief='flat', padx=10, pady=6,
            cursor='hand2', font=('Segoe UI', 10),
            command=self._manual_entry
        ).pack(side='left', padx=(6, 0))

        self.status_lbl = tk.Label(
            inner, text="Ready — scan a barcode or type a UPC and press Enter",
            bg=PANEL, fg=SUBTEXT, font=('Segoe UI', 10)
        )
        self.status_lbl.pack(side='left', padx=14)

    def _build_detail_panel(self, parent):
        self.detail_frame = tk.Frame(parent, bg=PANEL, width=300)
        self.detail_frame.pack(side='left', fill='y', padx=(0, 10))
        self.detail_frame.pack_propagate(False)

        p = self.detail_frame

        tk.Label(p, text="Item Details", bg=PANEL, fg=TEXT,
                 font=('Segoe UI', 11, 'bold')).pack(padx=14, pady=(14, 6), anchor='w')

        # Cover art area
        self.cover_lbl = tk.Label(
            p, bg=PANEL, text="[ no cover art ]",
            fg=BORDER, font=('Segoe UI', 9), width=28, height=7,
            relief='flat', bd=0
        )
        self.cover_lbl.pack(padx=14, pady=(0, 8))

        # Form
        form = tk.Frame(p, bg=PANEL)
        form.pack(fill='x', padx=14)

        def field(label, attr, kind='entry', opts=None, default=''):
            tk.Label(form, text=label, bg=PANEL, fg=SUBTEXT,
                     font=('Segoe UI', 8)).pack(anchor='w', pady=(5, 1))
            if kind == 'entry':
                var = tk.StringVar(value=default)
                setattr(self, attr, var)
                e = tk.Entry(form, textvariable=var,
                             bg=INPUT_BG, fg=TEXT, insertbackground=TEXT,
                             relief='flat', font=('Segoe UI', 10),
                             highlightthickness=1, highlightbackground=BORDER)
                e.pack(fill='x', ipady=4, ipadx=4)
                return e
            elif kind == 'combo':
                var = tk.StringVar(value=default or (opts[0] if opts else ''))
                setattr(self, attr, var)
                cb = ttk.Combobox(form, textvariable=var,
                                  values=opts, state='readonly',
                                  font=('Segoe UI', 10))
                cb.pack(fill='x')
                return cb

        cat_combo = field("Category", "v_category", 'combo', CATEGORIES, CATEGORIES[0])
        cat_combo.bind('<<ComboboxSelected>>', self._on_category_change)

        # Genre — options depend on category
        tk.Label(form, text="Genre", bg=PANEL, fg=SUBTEXT,
                 font=('Segoe UI', 8)).pack(anchor='w', pady=(5, 1))
        self.genre_var = tk.StringVar()
        self.genre_combo = ttk.Combobox(form, textvariable=self.genre_var,
                                        values=GENRES.get(CATEGORIES[0], []),
                                        state='readonly', font=('Segoe UI', 10))
        self.genre_combo.pack(fill='x')

        field("Title",            "v_title")
        field("Artist / Author",  "v_artist")
        field("Year",             "v_year")
        field("Label / Publisher","v_label")
        field("Condition",        "v_condition", 'combo', CONDITIONS, CONDITIONS[3])
        field("Quantity",         "v_quantity",  default='1')

        tk.Label(form, text="Notes", bg=PANEL, fg=SUBTEXT,
                 font=('Segoe UI', 8)).pack(anchor='w', pady=(5, 1))
        self.v_notes = tk.Text(form, bg=INPUT_BG, fg=TEXT,
                               insertbackground=TEXT,
                               relief='flat', font=('Segoe UI', 10),
                               height=3, wrap='word',
                               highlightthickness=1, highlightbackground=BORDER)
        self.v_notes.pack(fill='x', ipady=4, ipadx=4)

        # Action buttons
        btn_row = tk.Frame(p, bg=PANEL)
        btn_row.pack(fill='x', padx=14, pady=10)

        self.add_btn = tk.Button(
            btn_row, text="Add to Inventory",
            bg=SUCCESS, fg='#0a0a0a', relief='flat',
            padx=8, pady=7, cursor='hand2',
            font=('Segoe UI', 10, 'bold'), state='disabled',
            command=self._add_item
        )
        self.add_btn.pack(side='left', fill='x', expand=True, padx=(0, 4))

        self.clear_btn = tk.Button(
            btn_row, text="Clear",
            bg=PANEL, fg=SUBTEXT, relief='flat',
            padx=8, pady=7, cursor='hand2',
            font=('Segoe UI', 10), command=self._clear_detail
        )
        self.clear_btn.pack(side='left')

        # Edit-mode buttons (visible when table row selected)
        edit_row = tk.Frame(p, bg=PANEL)
        edit_row.pack(fill='x', padx=14, pady=(0, 10))

        self.save_btn = tk.Button(
            edit_row, text="Save Changes",
            bg=ACCENT, fg='#ffffff', relief='flat',
            padx=8, pady=7, cursor='hand2',
            font=('Segoe UI', 10, 'bold'), state='disabled',
            command=self._save_edit
        )
        self.save_btn.pack(side='left', fill='x', expand=True, padx=(0, 4))

        self.del_btn = tk.Button(
            edit_row, text="Delete",
            bg=DANGER, fg='#ffffff', relief='flat',
            padx=8, pady=7, cursor='hand2',
            font=('Segoe UI', 10), state='disabled',
            command=self._delete_item
        )
        self.del_btn.pack(side='left')

    def _build_inventory_panel(self, parent):
        right = tk.Frame(parent, bg=BG)
        right.pack(side='left', fill='both', expand=True)

        # Filter row
        filter_bar = tk.Frame(right, bg=BG)
        filter_bar.pack(fill='x', pady=(0, 6))

        tk.Label(filter_bar, text="Show:", bg=BG, fg=SUBTEXT,
                 font=('Segoe UI', 9)).pack(side='left', padx=(0, 4))

        for cat in ["All", "CD", "Book", "Blu-ray"]:
            tk.Radiobutton(
                filter_bar, text=cat,
                variable=self.filter_var, value=cat,
                bg=BG, fg=TEXT, selectcolor=ACCENT,
                activebackground=BG, font=('Segoe UI', 10),
                command=self._refresh_table
            ).pack(side='left', padx=2)

        tk.Label(filter_bar, text="Search:", bg=BG, fg=SUBTEXT,
                 font=('Segoe UI', 9)).pack(side='left', padx=(16, 4))

        self.search_entry = tk.Entry(
            filter_bar, textvariable=self.search_var,
            bg=INPUT_BG, fg=TEXT, insertbackground=TEXT,
            relief='flat', font=('Segoe UI', 10), width=22,
            highlightthickness=1, highlightbackground=BORDER
        )
        self.search_entry.pack(side='left', ipady=4, ipadx=4)

        self.count_lbl = tk.Label(filter_bar, text="", bg=BG, fg=SUBTEXT,
                                  font=('Segoe UI', 9))
        self.count_lbl.pack(side='right', padx=4)

        # Treeview
        tree_frame = tk.Frame(right, bg=BG)
        tree_frame.pack(fill='both', expand=True)

        cols = ('upc', 'title', 'category', 'genre', 'artist_author', 'year', 'qty', 'condition')
        heads = ('UPC / ISBN', 'Title', 'Category', 'Genre', 'Artist / Author', 'Year', 'Qty', 'Condition')
        widths = (130, 230, 75, 110, 170, 50, 38, 85)

        self.tree = ttk.Treeview(
            tree_frame, columns=cols, show='headings',
            selectmode='browse'
        )
        for col, head, w in zip(cols, heads, widths):
            self.tree.heading(col, text=head,
                              command=lambda c=col: self._sort_col(c))
            self.tree.column(col, width=w, minwidth=35)

        # Row colours per category
        for cat, colour in CAT_COLORS.items():
            self.tree.tag_configure(cat, background=colour)
        self.tree.tag_configure('odd', background=PANEL)

        vsb = ttk.Scrollbar(tree_frame, orient='vertical', command=self.tree.yview)
        self.tree.configure(yscrollcommand=vsb.set)
        self.tree.pack(side='left', fill='both', expand=True)
        vsb.pack(side='right', fill='y')

        self.tree.bind('<<TreeviewSelect>>', self._on_row_select)

        # Sort state
        self._sort_reverse: dict[str, bool] = {}

    def _build_status_bar(self):
        bar = tk.Frame(self, bg=PANEL)
        bar.pack(fill='x', padx=12, pady=(0, 12))

        self.lbl_total   = self._stat_label(bar, "Total: 0")
        self._sep(bar)
        self.lbl_cd      = self._stat_label(bar, "CDs: 0")
        self._sep(bar)
        self.lbl_book    = self._stat_label(bar, "Books: 0")
        self._sep(bar)
        self.lbl_bluray  = self._stat_label(bar, "Blu-ray: 0")

        tk.Label(bar, text=f"DB: {database.DB_PATH}",
                 bg=PANEL, fg=BORDER, font=('Segoe UI', 8)
                 ).pack(side='right', padx=10)

    @staticmethod
    def _stat_label(parent, text):
        lbl = tk.Label(parent, text=text, bg=PANEL, fg=SUBTEXT,
                       font=('Segoe UI', 9))
        lbl.pack(side='left', padx=10, pady=6)
        return lbl

    @staticmethod
    def _sep(parent):
        tk.Label(parent, text="|", bg=PANEL, fg=BORDER).pack(side='left')

    # ── Scan / lookup ──────────────────────────────────────────────────────────

    def _on_scan(self, _event=None):
        upc = self.scan_var.get().strip()
        if not upc:
            return
        log.info('Scan upc=%s', upc)
        valid, err = lookup.validate_barcode(upc)
        if not valid:
            log.info('Scan upc=%s rejected: %s', upc, err)
            self._set_status(f"Invalid barcode: {err}", DANGER)
            return
        self._set_status(f"Looking up {upc} ...", WARNING)
        self.scan_btn.config(state='disabled')
        self.add_btn.config(state='disabled')
        self.selected_id = None
        self.save_btn.config(state='disabled')
        self.del_btn.config(state='disabled')

        def worker():
            result = lookup.lookup_upc(upc)
            self.after(0, lambda: self._on_result(upc, result))

        threading.Thread(target=worker, daemon=True).start()

    def _on_result(self, upc: str, result: dict | None):
        self.scan_btn.config(state='normal')
        self.scan_var.set('')

        if result:
            self.current_scan = result
            self.current_scan['upc'] = upc

            cat = result.get('category', 'CD')
            if cat not in CATEGORIES:
                cat = 'CD'
            self.v_category.set(cat)
            self._on_category_change()
            self.genre_var.set(result.get('genre', ''))
            self.v_title.set(result.get('title', ''))
            self.v_artist.set(result.get('artist_author', ''))
            self.v_year.set(result.get('year', ''))
            self.v_label.set(result.get('publisher_label', ''))
            self.v_quantity.set('1')

            src = result.get('source', '')
            self._set_status(f"Found via {src}: {result.get('title', '')}", SUCCESS)
            self.add_btn.config(state='normal')

            if PIL_AVAILABLE and result.get('thumbnail_url'):
                threading.Thread(
                    target=self._load_cover,
                    args=(result['thumbnail_url'],),
                    daemon=True
                ).start()
        else:
            self.current_scan = {'upc': upc}
            self._set_status("Not found — fill in details and click Add", WARNING)
            self.v_title.set('')
            self.v_artist.set('')
            self.v_year.set('')
            self.v_label.set('')
            self.add_btn.config(state='normal')
            self.cover_lbl.config(image='', text='[ no cover art ]')

        self.scan_entry.focus_set()

    def _load_cover(self, url: str):
        try:
            import requests as req
            resp = req.get(url, timeout=8)
            if resp.status_code == 200:
                img = Image.open(io.BytesIO(resp.content))
                img.thumbnail((180, 220), Image.LANCZOS)
                photo = ImageTk.PhotoImage(img)
                self.after(0, lambda: self._set_cover(photo))
        except Exception:
            pass

    def _set_cover(self, photo):
        self.cover_lbl.config(image=photo, text='')
        self.cover_lbl.image = photo  # prevent GC

    def _manual_entry(self):
        """Open detail panel for a fully manual item with no barcode."""
        self.current_scan = {}
        self.selected_id = None
        self._clear_detail_fields()
        self.add_btn.config(state='normal')
        self.save_btn.config(state='disabled')
        self.del_btn.config(state='disabled')
        self.cover_lbl.config(image='', text='[ no cover art ]')
        self._set_status("Manual entry — fill in details and click Add", WARNING)

    # ── CRUD ───────────────────────────────────────────────────────────────────

    def _add_item(self):
        title = self.v_title.get().strip()
        if not title:
            messagebox.showwarning("Missing Title", "Please enter a title.")
            return

        try:
            qty = max(1, int(self.v_quantity.get() or '1'))
        except ValueError:
            qty = 1

        item = {
            'upc':             (self.current_scan or {}).get('upc', ''),
            'title':           title,
            'category':        self.v_category.get(),
            'genre':           self.genre_var.get(),
            'artist_author':   self.v_artist.get().strip(),
            'year':            self.v_year.get().strip(),
            'publisher_label': self.v_label.get().strip(),
            'thumbnail_url':   (self.current_scan or {}).get('thumbnail_url'),
            'quantity':        qty,
            'condition':       self.v_condition.get(),
            'notes':           self.v_notes.get('1.0', 'end-1c').strip(),
        }

        success, msg = database.add_item(item)
        color = SUCCESS if success else WARNING
        self._set_status(f"{msg}: {title}", color)
        self._refresh_table()
        self._update_stats()
        self._clear_detail()
        self.scan_entry.focus_set()

    def _save_edit(self):
        if self.selected_id is None:
            return
        title = self.v_title.get().strip()
        if not title:
            messagebox.showwarning("Missing Title", "Please enter a title.")
            return
        try:
            qty = max(1, int(self.v_quantity.get() or '1'))
        except ValueError:
            qty = 1

        database.update_item(
            self.selected_id,
            title=title,
            category=self.v_category.get(),
            genre=self.genre_var.get(),
            artist_author=self.v_artist.get().strip(),
            year=self.v_year.get().strip(),
            publisher_label=self.v_label.get().strip(),
            quantity=qty,
            condition=self.v_condition.get(),
            notes=self.v_notes.get('1.0', 'end-1c').strip(),
        )
        self._set_status(f"Saved: {title}", SUCCESS)
        self._refresh_table()
        self._update_stats()

    def _delete_item(self):
        if self.selected_id is None:
            return
        title = self.v_title.get() or "this item"
        if messagebox.askyesno("Confirm Delete",
                               f"Remove '{title}' from inventory?\nThis cannot be undone."):
            database.delete_item(self.selected_id)
            self._set_status(f"Deleted: {title}", DANGER)
            self._clear_detail()
            self._refresh_table()
            self._update_stats()

    # ── Table ──────────────────────────────────────────────────────────────────

    def _refresh_table(self, *_):
        for row in self.tree.get_children():
            self.tree.delete(row)

        cat    = self.filter_var.get()
        search = self.search_var.get().strip()

        items = database.get_all_items(
            category=cat if cat != "All" else None,
            search=search or None,
        )

        for item in items:
            tag = item.get('category', '') if item.get('category') in CAT_COLORS else 'odd'
            self.tree.insert('', 'end',
                values=(
                    item.get('upc') or '',
                    item.get('title', ''),
                    item.get('category', ''),
                    item.get('genre') or '',
                    item.get('artist_author') or '',
                    item.get('year') or '',
                    item.get('quantity', 1),
                    item.get('condition') or '',
                ),
                tags=(str(item['id']), tag),
            )

        self.count_lbl.config(text=f"{len(items)} item{'s' if len(items) != 1 else ''}")

    def _sort_col(self, col: str):
        reverse = self._sort_reverse.get(col, False)
        data = [(self.tree.set(child, col), child)
                for child in self.tree.get_children('')]
        try:
            data.sort(key=lambda t: float(t[0]) if t[0].isdigit() else t[0].lower(),
                      reverse=reverse)
        except Exception:
            data.sort(reverse=reverse)
        for i, (_, child) in enumerate(data):
            self.tree.move(child, '', i)
        self._sort_reverse[col] = not reverse

    def _on_row_select(self, _event=None):
        sel = self.tree.selection()
        if not sel:
            return
        tags = self.tree.item(sel[0], 'tags')
        # First tag is the item ID (we set it that way)
        item_id = None
        for t in tags:
            if t.isdigit():
                item_id = int(t)
                break
        if item_id is None:
            return

        item = database.get_item_by_id(item_id)
        if not item:
            return

        self.selected_id = item_id
        self.current_scan = None

        cat = item.get('category', CATEGORIES[0])
        self.v_category.set(cat if cat in CATEGORIES else CATEGORIES[0])
        self._on_category_change()
        self.genre_var.set(item.get('genre', '') or '')
        self.v_title.set(item.get('title', ''))
        self.v_artist.set(item.get('artist_author', '') or '')
        self.v_year.set(item.get('year', '') or '')
        self.v_label.set(item.get('publisher_label', '') or '')
        self.v_condition.set(item.get('condition', CONDITIONS[3]) or CONDITIONS[3])
        self.v_quantity.set(str(item.get('quantity', 1)))
        self.v_notes.delete('1.0', 'end')
        self.v_notes.insert('1.0', item.get('notes', '') or '')

        self.add_btn.config(state='disabled')
        self.save_btn.config(state='normal')
        self.del_btn.config(state='normal')

        # Load cover if available
        if PIL_AVAILABLE and item.get('thumbnail_url'):
            threading.Thread(
                target=self._load_cover,
                args=(item['thumbnail_url'],),
                daemon=True
            ).start()
        else:
            self.cover_lbl.config(image='', text='[ no cover art ]')

    # ── Helpers ────────────────────────────────────────────────────────────────

    def _on_category_change(self, _event=None):
        cat = self.v_category.get()
        self.genre_combo.configure(values=GENRES.get(cat, [""]))
        self.genre_var.set('')

    def _backup_db(self):
        dest = filedialog.asksaveasfilename(
            defaultextension=".db",
            filetypes=[("SQLite database", "*.db"), ("All files", "*.*")],
            initialfile="media_inventory_backup.db",
        )
        if dest:
            shutil.copy2(database.DB_PATH, dest)
            log.info('Backup DB -> %s', dest)
            messagebox.showinfo("Backup", f"Database backed up to:\n{dest}")

    def _open_log(self):
        path = applog.LOG_PATH
        if not os.path.exists(path):
            messagebox.showinfo("View Log", f"No log file yet at:\n{path}")
            return
        try:
            if sys.platform == 'win32':
                os.startfile(path)
            elif sys.platform == 'darwin':
                subprocess.Popen(['open', path])
            else:
                subprocess.Popen(['xdg-open', path])
        except Exception:
            log.exception('Failed to open log file')
            messagebox.showerror("View Log", f"Could not open:\n{path}")

    def _clear_detail(self):
        self.current_scan = None
        self.selected_id = None
        self._clear_detail_fields()
        self.add_btn.config(state='disabled')
        self.save_btn.config(state='disabled')
        self.del_btn.config(state='disabled')
        self.cover_lbl.config(image='', text='[ no cover art ]')

    def _clear_detail_fields(self):
        self.v_title.set('')
        self.v_artist.set('')
        self.v_year.set('')
        self.v_label.set('')
        self.v_quantity.set('1')
        self.v_category.set(CATEGORIES[0])
        self._on_category_change()
        self.genre_var.set('')
        self.v_condition.set(CONDITIONS[3])
        self.v_notes.delete('1.0', 'end')

    def _focus_scan(self):
        self.scan_var.set('')
        self.scan_entry.focus_set()

    def _set_status(self, msg: str, color: str = SUBTEXT):
        self.status_lbl.config(text=msg, fg=color)

    def _update_stats(self):
        s = database.get_stats()
        self.lbl_total.config(text=f"Total: {s['total']} titles  ({s['total_qty']} qty)")
        self.lbl_cd.config(text=f"CDs: {s['CD']}")
        self.lbl_book.config(text=f"Books: {s['Book']}")
        self.lbl_bluray.config(text=f"Blu-ray: {s['Blu-ray']}")

    def _export_csv(self):
        path = filedialog.asksaveasfilename(
            defaultextension='.csv',
            filetypes=[('CSV', '*.csv'), ('All files', '*.*')],
            initialfile=f'media_inventory_{datetime.now().strftime("%Y%m%d")}.csv'
        )
        if not path:
            return
        items = database.get_all_items()
        if not items:
            messagebox.showinfo("Export", "No items to export.")
            return
        fields = ['id', 'upc', 'title', 'category', 'artist_author',
                  'year', 'publisher_label', 'quantity', 'condition',
                  'notes', 'added_date']
        with open(path, 'w', newline='', encoding='utf-8') as f:
            w = csv.DictWriter(f, fieldnames=fields, extrasaction='ignore')
            w.writeheader()
            w.writerows(items)
        log.info('Exported %d items to %s', len(items), path)
        self._set_status(f"Exported {len(items)} items -> {os.path.basename(path)}", SUCCESS)
        messagebox.showinfo("Export Complete",
                            f"Exported {len(items)} items to:\n{path}")


# ──────────────────────────────────────────────────────────────────────────────
if __name__ == '__main__':
    app = App()
    app.mainloop()
