"""
Application logging for Media Inventory Scanner.

Activity (scans, lookups, DB writes) and uncaught exceptions go to
<db_dir>/media_inventory.log via a rotating file handler. The log
lives next to the database so it gets synced together when the DB is
in OneDrive/Dropbox/etc.

Set MEDIA_INVENTORY_DEBUG=1 to bump file logging to DEBUG.
"""

from __future__ import annotations

import logging
import os
import sys
from logging.handlers import RotatingFileHandler

import database

LOG_PATH = os.path.join(os.path.dirname(database.DB_PATH), 'media_inventory.log')

_configured = False


def setup_logging() -> str:
    global _configured
    if _configured:
        return LOG_PATH

    parent = os.path.dirname(LOG_PATH)
    if parent and not os.path.exists(parent):
        os.makedirs(parent, exist_ok=True)

    level = logging.DEBUG if os.environ.get('MEDIA_INVENTORY_DEBUG') else logging.INFO

    handler = RotatingFileHandler(
        LOG_PATH, maxBytes=2_000_000, backupCount=5, encoding='utf-8'
    )
    handler.setLevel(level)
    handler.setFormatter(logging.Formatter(
        '%(asctime)s %(levelname)-7s %(name)-10s %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S',
    ))

    root = logging.getLogger()
    root.setLevel(level)
    root.addHandler(handler)

    def _hook(exc_type, exc, tb):
        if issubclass(exc_type, KeyboardInterrupt):
            sys.__excepthook__(exc_type, exc, tb)
            return
        logging.getLogger('uncaught').critical(
            'Uncaught exception', exc_info=(exc_type, exc, tb)
        )
    sys.excepthook = _hook

    _configured = True
    logging.getLogger('startup').info(
        'Logging initialized at %s (level=%s)',
        LOG_PATH, logging.getLevelName(level),
    )
    return LOG_PATH


def install_tk_excepthook(tk_root) -> None:
    log = logging.getLogger('tk')
    def _report(exc, val, tb):
        log.critical('Tk callback exception', exc_info=(exc, val, tb))
    tk_root.report_callback_exception = _report
