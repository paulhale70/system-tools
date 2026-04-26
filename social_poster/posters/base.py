from dataclasses import dataclass
from typing import Optional


@dataclass
class PostResult:
    platform: str
    ok: bool
    message: str
    url: Optional[str] = None

    def to_dict(self) -> dict:
        return {
            "platform": self.platform,
            "ok": self.ok,
            "message": self.message,
            "url": self.url,
        }


class PosterError(Exception):
    pass
