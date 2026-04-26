import os
import re
from typing import Optional

from .base import PostResult, PosterError

PLATFORM = "bluesky"
MAX_GRAPHEMES = 300  # Bluesky enforces a graphemes-based limit; chars is a close proxy.


class BlueskyPoster:
    def __init__(self) -> None:
        self.handle = os.getenv("BLUESKY_HANDLE", "").strip()
        self.app_password = os.getenv("BLUESKY_APP_PASSWORD", "").strip()

    @property
    def configured(self) -> bool:
        return bool(self.handle and self.app_password)

    def post(self, text: str, image_path: Optional[str] = None) -> PostResult:
        if not self.configured:
            return PostResult(PLATFORM, False, "Not configured")

        if len(text) > MAX_GRAPHEMES:
            return PostResult(
                PLATFORM,
                False,
                f"Post exceeds {MAX_GRAPHEMES} characters ({len(text)})",
            )

        try:
            from atproto import Client, client_utils
        except ImportError as e:
            raise PosterError(f"atproto not installed: {e}")

        try:
            client = Client()
            client.login(self.handle, self.app_password)

            text_builder = _build_rich_text(text, client_utils)

            if image_path:
                with open(image_path, "rb") as f:
                    img_bytes = f.read()
                response = client.send_image(
                    text=text_builder,
                    image=img_bytes,
                    image_alt="",
                )
            else:
                response = client.send_post(text=text_builder)

            uri = getattr(response, "uri", None)
            url = _at_uri_to_web_url(uri, self.handle) if uri else None
            return PostResult(PLATFORM, True, "Posted", url=url)
        except Exception as e:
            return PostResult(PLATFORM, False, str(e))


_LINK_RE = re.compile(r"https?://[^\s]+")


def _build_rich_text(text: str, client_utils):
    """Build a TextBuilder that auto-detects URLs as facets."""
    builder = client_utils.TextBuilder()
    pos = 0
    for match in _LINK_RE.finditer(text):
        if match.start() > pos:
            builder.text(text[pos:match.start()])
        builder.link(match.group(0), match.group(0))
        pos = match.end()
    if pos < len(text):
        builder.text(text[pos:])
    return builder


def _at_uri_to_web_url(uri: str, handle: str) -> Optional[str]:
    # at://did:plc:.../app.bsky.feed.post/<rkey>
    parts = uri.split("/")
    if len(parts) >= 1:
        rkey = parts[-1]
        return f"https://bsky.app/profile/{handle}/post/{rkey}"
    return None
