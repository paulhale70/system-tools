import os
from typing import Optional

from .base import PostResult, PosterError

PLATFORM = "twitter"
MAX_CHARS = 280


class TwitterPoster:
    def __init__(self) -> None:
        self.api_key = os.getenv("TWITTER_API_KEY", "").strip()
        self.api_secret = os.getenv("TWITTER_API_SECRET", "").strip()
        self.access_token = os.getenv("TWITTER_ACCESS_TOKEN", "").strip()
        self.access_token_secret = os.getenv("TWITTER_ACCESS_TOKEN_SECRET", "").strip()

    @property
    def configured(self) -> bool:
        return all(
            [self.api_key, self.api_secret, self.access_token, self.access_token_secret]
        )

    def post(self, text: str, image_path: Optional[str] = None) -> PostResult:
        if not self.configured:
            return PostResult(PLATFORM, False, "Not configured")

        if len(text) > MAX_CHARS:
            return PostResult(
                PLATFORM, False, f"Tweet exceeds {MAX_CHARS} characters ({len(text)})"
            )

        try:
            import tweepy
        except ImportError as e:
            raise PosterError(f"tweepy not installed: {e}")

        try:
            client = tweepy.Client(
                consumer_key=self.api_key,
                consumer_secret=self.api_secret,
                access_token=self.access_token,
                access_token_secret=self.access_token_secret,
            )

            media_ids = None
            if image_path:
                # v1.1 endpoint is still required for media uploads.
                auth = tweepy.OAuth1UserHandler(
                    self.api_key,
                    self.api_secret,
                    self.access_token,
                    self.access_token_secret,
                )
                api_v1 = tweepy.API(auth)
                media = api_v1.media_upload(filename=image_path)
                media_ids = [media.media_id]

            response = client.create_tweet(text=text, media_ids=media_ids)
            tweet_id = response.data.get("id")
            url = f"https://x.com/i/status/{tweet_id}" if tweet_id else None
            return PostResult(PLATFORM, True, "Posted", url=url)
        except Exception as e:
            return PostResult(PLATFORM, False, str(e))
