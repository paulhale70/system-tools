import sqlite3
import json
import os
from datetime import datetime

CONFIG_PATH = os.path.join(os.path.expanduser("~"), ".media_inventory_config.json")
DEFAULT_DB_PATH = os.path.join(os.path.expanduser("~"), "media_inventory.db")


def _resolve_db_path() -> str:
    env = os.environ.get("MEDIA_INVENTORY_DB")
    if env:
        return os.path.expanduser(env)
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                cfg = json.load(f)
            path = cfg.get("db_path")
            if path:
                return os.path.expanduser(path)
        except Exception:
            pass
    return DEFAULT_DB_PATH


DB_PATH = _resolve_db_path()


def get_connection():
    parent = os.path.dirname(DB_PATH)
    if parent and not os.path.exists(parent):
        os.makedirs(parent, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    with get_connection() as conn:
        conn.execute('''
            CREATE TABLE IF NOT EXISTS items (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                upc             TEXT,
                title           TEXT NOT NULL,
                category        TEXT NOT NULL,
                artist_author   TEXT,
                year            TEXT,
                publisher_label TEXT,
                thumbnail_url   TEXT,
                quantity        INTEGER DEFAULT 1,
                condition       TEXT DEFAULT 'Good',
                notes           TEXT,
                added_date      TEXT,
                updated_date    TEXT
            )
        ''')

        # Migration: add genre column to existing databases
        try:
            conn.execute("ALTER TABLE items ADD COLUMN genre TEXT DEFAULT ''")
        except Exception:
            pass  # column already exists

        conn.execute('''
            CREATE TABLE IF NOT EXISTS lookup_cache (
                upc       TEXT PRIMARY KEY,
                result    TEXT NOT NULL,
                cached_at TEXT NOT NULL
            )
        ''')

        conn.commit()


# ── Lookup cache ───────────────────────────────────────────────────────────────

def cache_get(upc: str) -> dict | None:
    """Return cached lookup result for upc, or None if not cached."""
    with get_connection() as conn:
        row = conn.execute(
            "SELECT result FROM lookup_cache WHERE upc = ?", (upc,)
        ).fetchone()
        if row:
            try:
                return json.loads(row['result'])
            except Exception:
                return None
    return None


def cache_set(upc: str, result: dict) -> None:
    """Store a lookup result in the cache."""
    with get_connection() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO lookup_cache (upc, result, cached_at) VALUES (?, ?, ?)",
            (upc, json.dumps(result), datetime.now().isoformat())
        )
        conn.commit()


# ── Item CRUD ──────────────────────────────────────────────────────────────────

def add_item(item):
    now = datetime.now().isoformat()
    upc = (item.get('upc') or '').strip()

    with get_connection() as conn:
        if upc:
            existing = conn.execute(
                "SELECT id FROM items WHERE upc = ?", (upc,)
            ).fetchone()
            if existing:
                conn.execute(
                    "UPDATE items SET quantity = quantity + 1, updated_date = ? WHERE upc = ?",
                    (now, upc)
                )
                conn.commit()
                return False, "Item already exists — quantity incremented"

        conn.execute('''
            INSERT INTO items
                (upc, title, category, genre, artist_author, year, publisher_label,
                 thumbnail_url, quantity, condition, notes, added_date, updated_date)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            upc or None,
            item['title'],
            item['category'],
            item.get('genre', ''),
            item.get('artist_author', ''),
            item.get('year', ''),
            item.get('publisher_label', ''),
            item.get('thumbnail_url'),
            item.get('quantity', 1),
            item.get('condition', 'Good'),
            item.get('notes', ''),
            now,
            now,
        ))
        conn.commit()
        return True, "Item added successfully"


def get_all_items(category=None, search=None):
    with get_connection() as conn:
        query = "SELECT * FROM items"
        params = []
        conditions = []

        if category and category != "All":
            conditions.append("category = ?")
            params.append(category)

        if search:
            conditions.append(
                "(title LIKE ? OR artist_author LIKE ? OR upc LIKE ? OR publisher_label LIKE ?)"
            )
            like = f'%{search}%'
            params.extend([like, like, like, like])

        if conditions:
            query += " WHERE " + " AND ".join(conditions)

        query += " ORDER BY added_date DESC"
        cursor = conn.execute(query, params)
        return [dict(row) for row in cursor.fetchall()]


def get_item_by_id(item_id):
    with get_connection() as conn:
        row = conn.execute("SELECT * FROM items WHERE id = ?", (item_id,)).fetchone()
        return dict(row) if row else None


def update_item(item_id, **kwargs):
    kwargs['updated_date'] = datetime.now().isoformat()
    set_clause = ", ".join(f"{k} = ?" for k in kwargs)
    values = list(kwargs.values()) + [item_id]
    with get_connection() as conn:
        conn.execute(f"UPDATE items SET {set_clause} WHERE id = ?", values)
        conn.commit()


def delete_item(item_id):
    with get_connection() as conn:
        conn.execute("DELETE FROM items WHERE id = ?", (item_id,))
        conn.commit()


def get_stats():
    with get_connection() as conn:
        total = conn.execute("SELECT COUNT(*) FROM items").fetchone()[0]
        total_qty = conn.execute("SELECT COALESCE(SUM(quantity), 0) FROM items").fetchone()[0]
        stats = {'total': total, 'total_qty': total_qty}
        for cat in ['CD', 'Book', 'Blu-ray']:
            stats[cat] = conn.execute(
                "SELECT COUNT(*) FROM items WHERE category = ?", (cat,)
            ).fetchone()[0]
        return stats
