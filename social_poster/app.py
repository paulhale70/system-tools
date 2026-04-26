import os
import secrets
import tempfile
from pathlib import Path

from dotenv import load_dotenv
from flask import Flask, jsonify, render_template, request

# Load .env from this module's directory regardless of where Flask is launched.
_HERE = Path(__file__).resolve().parent
load_dotenv(_HERE / ".env")

from posters import BlueskyPoster, FacebookPoster, TwitterPoster  # noqa: E402

ALLOWED_IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".gif", ".webp"}
MAX_IMAGE_BYTES = 8 * 1024 * 1024  # 8 MB
MAX_TEXT_LEN = 5000  # outer cap; per-platform limits enforced in posters

PLATFORM_CLASSES = {
    "twitter": TwitterPoster,
    "bluesky": BlueskyPoster,
    "facebook": FacebookPoster,
}


def create_app() -> Flask:
    app = Flask(__name__, static_folder="static", template_folder="templates")
    app.secret_key = os.getenv("FLASK_SECRET_KEY") or secrets.token_hex(32)

    @app.get("/")
    def index():
        status = {name: cls().configured for name, cls in PLATFORM_CLASSES.items()}
        return render_template("index.html", status=status)

    @app.get("/api/status")
    def status():
        return jsonify({name: cls().configured for name, cls in PLATFORM_CLASSES.items()})

    @app.post("/api/post")
    def post():
        text = (request.form.get("text") or "").strip()
        platforms = request.form.getlist("platforms")
        image_file = request.files.get("image")

        if not text and not image_file:
            return jsonify({"error": "Post text or image is required."}), 400
        if len(text) > MAX_TEXT_LEN:
            return jsonify({"error": f"Text exceeds {MAX_TEXT_LEN} characters."}), 400
        if not platforms:
            return jsonify({"error": "Select at least one platform."}), 400

        unknown = [p for p in platforms if p not in PLATFORM_CLASSES]
        if unknown:
            return jsonify({"error": f"Unknown platform(s): {', '.join(unknown)}"}), 400

        image_path = None
        tmp_handle = None
        if image_file and image_file.filename:
            ext = Path(image_file.filename).suffix.lower()
            if ext not in ALLOWED_IMAGE_EXTS:
                return jsonify({"error": f"Unsupported image type: {ext}"}), 400
            blob = image_file.read()
            if len(blob) > MAX_IMAGE_BYTES:
                return jsonify({"error": "Image exceeds 8 MB limit."}), 400
            tmp_handle = tempfile.NamedTemporaryFile(delete=False, suffix=ext)
            tmp_handle.write(blob)
            tmp_handle.flush()
            tmp_handle.close()
            image_path = tmp_handle.name

        results = []
        try:
            for name in platforms:
                poster = PLATFORM_CLASSES[name]()
                result = poster.post(text, image_path=image_path)
                results.append(result.to_dict())
        finally:
            if image_path:
                try:
                    os.unlink(image_path)
                except OSError:
                    pass

        any_ok = any(r["ok"] for r in results)
        return jsonify({"ok": any_ok, "results": results})

    return app


if __name__ == "__main__":
    app = create_app()
    host = os.getenv("HOST", "127.0.0.1")
    port = int(os.getenv("PORT", "5000"))
    app.run(host=host, port=port, debug=False)
