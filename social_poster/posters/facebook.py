import os
from typing import Optional

import requests

from .base import PostResult

PLATFORM = "facebook"
GRAPH_API = "https://graph.facebook.com/v19.0"


class FacebookPoster:
    def __init__(self) -> None:
        self.page_id = os.getenv("FACEBOOK_PAGE_ID", "").strip()
        self.access_token = os.getenv("FACEBOOK_PAGE_ACCESS_TOKEN", "").strip()

    @property
    def configured(self) -> bool:
        return bool(self.page_id and self.access_token)

    def post(self, text: str, image_path: Optional[str] = None) -> PostResult:
        if not self.configured:
            return PostResult(PLATFORM, False, "Not configured")

        try:
            if image_path:
                url = f"{GRAPH_API}/{self.page_id}/photos"
                with open(image_path, "rb") as f:
                    files = {"source": f}
                    data = {"caption": text, "access_token": self.access_token}
                    resp = requests.post(url, data=data, files=files, timeout=30)
            else:
                url = f"{GRAPH_API}/{self.page_id}/feed"
                data = {"message": text, "access_token": self.access_token}
                resp = requests.post(url, data=data, timeout=30)

            if resp.status_code >= 400:
                err = _extract_error(resp)
                return PostResult(PLATFORM, False, err)

            payload = resp.json()
            post_id = payload.get("post_id") or payload.get("id")
            web_url = None
            if post_id and "_" in post_id:
                pid_only = post_id.split("_", 1)[1]
                web_url = f"https://www.facebook.com/{self.page_id}/posts/{pid_only}"
            return PostResult(PLATFORM, True, "Posted", url=web_url)
        except Exception as e:
            return PostResult(PLATFORM, False, str(e))


def _extract_error(resp: requests.Response) -> str:
    try:
        data = resp.json()
        err = data.get("error", {})
        return err.get("message") or f"HTTP {resp.status_code}"
    except Exception:
        return f"HTTP {resp.status_code}: {resp.text[:200]}"
