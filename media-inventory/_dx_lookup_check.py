"""Diagnostic helper invoked by collect-diagnostics.ps1.

Runs the full lookup pipeline against a known-good UPC and reports the
result or traceback. Run from the project root so `import lookup` works.
"""
import json
import os
import sys
import time
import traceback

sys.path.insert(0, os.getcwd())
import lookup

# Pink Floyd, "Dark Side of the Moon" CD reissue.
KNOWN_GOOD_UPC = "828766516920"

t0 = time.time()
try:
    result = lookup.lookup_upc(KNOWN_GOOD_UPC)
    print("ELAPSED:", round(time.time() - t0, 2), "s")
    print("RESULT:", json.dumps(result, default=str, indent=2)[:2000])
except Exception:
    print("ELAPSED:", round(time.time() - t0, 2), "s")
    print("ERROR:")
    traceback.print_exc()
