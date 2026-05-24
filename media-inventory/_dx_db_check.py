"""Diagnostic helper invoked by collect-diagnostics.ps1.

Resolves database.DB_PATH, then opens the file and reports integrity,
row counts, and schema. Run from the project root so `import database`
works.
"""
import json
import os
import sqlite3
import sys

sys.path.insert(0, os.getcwd())
import database

print("RESOLVED:", database.DB_PATH)
print("EXISTS:", os.path.exists(database.DB_PATH))

if os.path.exists(database.DB_PATH):
    print("SIZE:", os.path.getsize(database.DB_PATH))
    try:
        c = sqlite3.connect(database.DB_PATH)
        c.row_factory = sqlite3.Row
        print("INTEGRITY:", c.execute("PRAGMA integrity_check").fetchone()[0])
        print("QUICK:", c.execute("PRAGMA quick_check").fetchone()[0])
        for t in ("items", "lookup_cache"):
            try:
                n = c.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
                print(f"COUNT[{t}]:", n)
            except Exception as e:
                print(f"COUNT[{t}]: ERROR {e}")
        try:
            stats = {}
            for cat in ("CD", "Book", "Blu-ray"):
                stats[cat] = c.execute(
                    "SELECT COUNT(*) FROM items WHERE category = ?", (cat,)
                ).fetchone()[0]
            print("BY_CATEGORY:", json.dumps(stats))
        except Exception as e:
            print("BY_CATEGORY: ERROR", e)
        print("--- schema ---")
        for row in c.execute(
            "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL"
        ).fetchall():
            print(row[0])
        c.close()
    except Exception as e:
        print("OPEN_ERROR:", e)
