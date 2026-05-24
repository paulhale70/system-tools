from __future__ import annotations

"""
Barcode/UPC/ISBN lookup using free APIs (no API key required).

Priority order:
  1. UPC Item DB  — covers all product types (100 free lookups/day)
  2. Google Books — ISBN-13 books (1 000 free lookups/day per IP)
  3. Open Library — ISBN books, unlimited
  4. MusicBrainz  — CDs, 1 req/sec rate limit
"""

import logging
import time

import database as _db

log = logging.getLogger(__name__)

try:
    import requests
    REQUESTS_AVAILABLE = True
except ImportError:
    REQUESTS_AVAILABLE = False

HEADERS = {
    'User-Agent': 'MediaInventoryApp/1.0 (personal-use collector tool)'
}
TIMEOUT = 10


def validate_barcode(upc: str) -> tuple[bool, str]:
    """Return (True, '') if upc looks like a valid barcode, else (False, reason)."""
    upc = upc.strip()
    if not upc:
        return False, "Please enter a barcode"
    # ISBN-10: 10 chars, first 9 digits, last digit or 'X'
    if len(upc) == 10:
        body, check = upc[:9], upc[9].upper()
        if body.isdigit() and (check.isdigit() or check == 'X'):
            return True, ""
        return False, "ISBN-10 must be 9 digits followed by a digit or X"
    # All other formats must be digits only
    if not upc.isdigit():
        return False, "Barcode must contain digits only"
    if len(upc) == 6:   # UPC-E short form
        return True, ""
    if len(upc) == 8:   # EAN-8
        return True, ""
    if len(upc) == 12:  # UPC-A
        return True, ""
    if len(upc) == 13:  # EAN-13 / ISBN-13
        return True, ""
    return False, f"Unrecognized barcode length ({len(upc)}); expected 6, 8, 10, 12, or 13"


def lookup_upc(upc: str) -> dict | None:
    """Return a result dict or None if nothing found."""
    if not REQUESTS_AVAILABLE:
        return None

    upc = upc.strip()
    if not upc:
        return None

    log.info('Lookup start upc=%s', upc)

    cached = _db.cache_get(upc)
    if cached:
        log.info('Lookup upc=%s served from cache (source=%s)',
                 upc, cached.get('source', '?'))
        return cached

    def _try(name, fn, *args):
        t = time.perf_counter()
        result = fn(*args)
        elapsed_ms = int((time.perf_counter() - t) * 1000)
        if result:
            log.info('Lookup upc=%s matched via %s in %dms', upc, name, elapsed_ms)
            _db.cache_set(upc, result)
        else:
            log.debug('Lookup upc=%s miss via %s in %dms', upc, name, elapsed_ms)
        return result

    result = _try('UPCitemdb', _upcitemdb, upc)
    if result:
        return result

    if len(upc) in (10, 13) and (len(upc) == 10 or upc[:3] in ('978', '979')):
        result = _try('GoogleBooks', _google_books, upc)
        if result:
            return result

    if len(upc) in (10, 13):
        result = _try('OpenLibrary', _open_library, upc)
        if result:
            return result

    result = _try('MusicBrainz', _musicbrainz, upc)
    if result:
        return result

    log.info('Lookup upc=%s exhausted all sources, no match', upc)
    return None


# ──────────────────────────────────────────────────────────────────────────────
# Individual API helpers
# ──────────────────────────────────────────────────────────────────────────────

def _upcitemdb(upc: str) -> dict | None:
    try:
        resp = requests.get(
            f'https://api.upcitemdb.com/prod/trial/lookup?upc={upc}',
            headers=HEADERS, timeout=TIMEOUT
        )
        if resp.status_code == 200:
            data = resp.json()
            items = data.get('items') or []
            if items:
                item = items[0]
                category = _detect_category(
                    item.get('category', ''),
                    item.get('title', ''),
                    item.get('description', ''),
                )
                images = item.get('images') or []
                return {
                    'title':           item.get('title', ''),
                    'category':        category,
                    'artist_author':   item.get('brand', '') or item.get('manufacturer', ''),
                    'year':            '',
                    'publisher_label': item.get('publisher', '') or item.get('brand', ''),
                    'thumbnail_url':   images[0] if images else None,
                    'description':     item.get('description', ''),
                    'source':          'UPC Item DB',
                }
        elif resp.status_code == 429:
            log.warning('UPCitemdb rate limit reached (100/day on free tier)')
    except Exception:
        log.exception('UPCitemdb request failed for upc=%s', upc)
    return None


def _google_books(isbn: str) -> dict | None:
    try:
        resp = requests.get(
            f'https://www.googleapis.com/books/v1/volumes?q=isbn:{isbn}',
            headers=HEADERS, timeout=TIMEOUT
        )
        if resp.status_code == 200:
            data = resp.json()
            items = data.get('items') or []
            if items:
                info = items[0].get('volumeInfo', {})
                authors = ', '.join(info.get('authors', []))
                thumb = (info.get('imageLinks') or {}).get('thumbnail', '')
                if thumb:
                    thumb = thumb.replace('http://', 'https://')
                    # Higher-res version
                    thumb = thumb.replace('&zoom=1', '&zoom=3')
                return {
                    'title':           info.get('title', ''),
                    'category':        'Book',
                    'artist_author':   authors,
                    'year':            (info.get('publishedDate') or '')[:4],
                    'publisher_label': info.get('publisher', ''),
                    'thumbnail_url':   thumb or None,
                    'description':     info.get('description', ''),
                    'source':          'Google Books',
                }
    except Exception:
        log.exception('Google Books request failed for isbn=%s', isbn)
    return None


def _open_library(isbn: str) -> dict | None:
    try:
        resp = requests.get(
            f'https://openlibrary.org/api/books?bibkeys=ISBN:{isbn}&format=json&jscmd=data',
            headers=HEADERS, timeout=TIMEOUT
        )
        if resp.status_code == 200:
            data = resp.json()
            key = f'ISBN:{isbn}'
            if key in data:
                book = data[key]
                authors = ', '.join(a['name'] for a in book.get('authors', []))
                publishers = ', '.join(p['name'] for p in book.get('publishers', []))
                cover = (book.get('cover') or {})
                thumb = cover.get('large') or cover.get('medium') or cover.get('small')
                return {
                    'title':           book.get('title', ''),
                    'category':        'Book',
                    'artist_author':   authors,
                    'year':            book.get('publish_date', ''),
                    'publisher_label': publishers,
                    'thumbnail_url':   thumb,
                    'description':     '',
                    'source':          'Open Library',
                }
    except Exception:
        log.exception('Open Library request failed for isbn=%s', isbn)
    return None


def _musicbrainz(upc: str) -> dict | None:
    try:
        time.sleep(1.1)  # MusicBrainz: max 1 req/sec
        resp = requests.get(
            f'https://musicbrainz.org/ws/2/release/?query=barcode:{upc}&fmt=json',
            headers=HEADERS, timeout=TIMEOUT
        )
        if resp.status_code == 200:
            data = resp.json()
            releases = data.get('releases') or []
            if releases:
                r = releases[0]
                artist = ''
                credits = r.get('artist-credit') or []
                if credits:
                    artist = credits[0].get('artist', {}).get('name', '')
                year = (r.get('date') or '')[:4]
                label = ''
                label_info = r.get('label-info') or []
                if label_info:
                    label = (label_info[0].get('label') or {}).get('name', '')
                return {
                    'title':           r.get('title', ''),
                    'category':        'CD',
                    'artist_author':   artist,
                    'year':            year,
                    'publisher_label': label,
                    'thumbnail_url':   None,
                    'description':     '',
                    'source':          'MusicBrainz',
                }
    except Exception:
        log.exception('MusicBrainz request failed for upc=%s', upc)
    return None


# ──────────────────────────────────────────────────────────────────────────────

def _detect_category(category: str, title: str, description: str) -> str:
    text = ' '.join([category, title, description]).lower()
    if any(w in text for w in ['blu-ray', 'blu ray', 'bluray']):
        return 'Blu-ray'
    if any(w in text for w in ['dvd', 'movie', 'film', 'video']):
        return 'Blu-ray'   # best guess if only DVD info available
    if any(w in text for w in [' cd', 'audio cd', 'music', 'album', 'soundtrack']):
        return 'CD'
    if any(w in text for w in ['book', 'paperback', 'hardcover', 'novel', 'isbn']):
        return 'Book'
    return 'Unknown'
