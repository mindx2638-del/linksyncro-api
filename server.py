import os
import time
import json
import random
import hashlib
import logging
import asyncio
import yt_dlp

from urllib.parse import urlparse
from concurrent.futures import ThreadPoolExecutor

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware

# =========================================================
# APP INITIALIZATION
# =========================================================

app = FastAPI(
    title="LinkSyncro Media API",
    version="2.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["GET"],
    allow_headers=["*"],
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)

executor = ThreadPoolExecutor(max_workers=25)

# =========================================================
# CONFIG
# =========================================================

CACHE = {}
CACHE_TTL = 1200  # 20 min

RATE_STORE = {}
RATE_LIMIT = 50
RATE_WINDOW = 60

VALID_API_KEYS = {"demo_key_123", "premium_key_456"}

USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/123.0.0.0 Safari/537.36",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 Version/17.4",
    "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 Chrome/90.0.4430.91",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/122.0.0.0"
]

ALLOWED_DOMAINS = [
    "youtube.com",
    "youtu.be",
    "facebook.com",
    "fb.watch",
    "fb.com",
    "instagram.com",
    "tiktok.com"
]

# =========================================================
# HELPERS
# =========================================================

def is_valid_url(url: str) -> bool:
    try:
        parsed = urlparse(url)

        if parsed.scheme not in ("http", "https") or not parsed.hostname:
            return False

        domain = parsed.hostname.replace("www.", "")
        return any(d in domain for d in ALLOWED_DOMAINS)

    except Exception:
        return False

def build_cache_key(url: str, quality: str) -> str:
    return hashlib.md5(f"{url}_{quality}".encode()).hexdigest()

def get_cached(cache_key: str):
    item = CACHE.get(cache_key)
    if not item:
        return None

    data, ts = item
    if time.time() - ts < CACHE_TTL:
        return data

    return None

def set_cache(cache_key: str, data: dict):
    CACHE[cache_key] = (data, time.time())

    if len(CACHE) > 1000:
        CACHE.pop(next(iter(CACHE)))

# =========================================================
# CORE ENGINE
# =========================================================

def extract_media(url: str, quality_preset: str = "720"):
    cache_key = build_cache_key(url, quality_preset)

    cached = get_cached(cache_key)
    if cached:
        logging.info(f"Cache Hit ({quality_preset}): {url}")
        return cached

    fb_cookies = "facebook_cookies.txt"
    yt_cookies = "youtube_cookies.txt"
    ig_cookies = "instagram_cookies.txt"

    if quality_preset in ("best", "2160"):
        format_selector = (
            "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best"
        )
    else:
        format_selector = (
            f"bestvideo[height<={quality_preset}][ext=mp4]+bestaudio[ext=m4a]/"
            f"best[height<={quality_preset}][ext=mp4]/best"
        )

    ydl_opts = {
        "format": format_selector,
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "socket_timeout": 45,
        "retries": 5,
        "nocheckcertificate": True,
        "geo_bypass": True,
        "user_agent": random.choice(USER_AGENTS),
        "http_headers": {
            "Accept": "*/*",
            "Accept-Language": "en-US,en;q=0.5",
            "Referer": "https://www.google.com/"
        },
        "extractor_args": {
            "youtube": {
                "player_client": ["android", "ios", "mweb"],
                "player_skip": ["webpage", "configs"]
            },
            "instagram": {
                "force_subtitles": False
            }
        }
    }

    domain = urlparse(url).hostname or ""

    if any(d in domain for d in ["facebook.com", "fb.watch", "fb.com"]):
        if os.path.exists(fb_cookies):
            ydl_opts["cookiefile"] = fb_cookies

    elif any(d in domain for d in ["youtube.com", "youtu.be"]):
        if os.path.exists(yt_cookies):
            ydl_opts["cookiefile"] = yt_cookies

    elif "instagram.com" in domain:
        if os.path.exists(ig_cookies):
            ydl_opts["cookiefile"] = ig_cookies

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)

            download_url = info.get("url")

            if not download_url and "formats" in info:
                formats = info["formats"]

                valid_formats = [
                    f for f in formats
                    if f.get("vcodec") != "none" and f.get("acodec") != "none"
                ]

                if not valid_formats:
                    valid_formats = [f for f in formats if f.get("url")]

                if valid_formats:
                    valid_formats.sort(
                        key=lambda x: (x.get("height") or 0),
                        reverse=True
                    )
                    download_url = valid_formats[0]["url"]

            if not download_url:
                return None

            result = {
                "status": "success",
                "url": download_url,
                "title": info.get("title", "Video"),
                "thumbnail": info.get("thumbnail"),
                "duration": info.get("duration"),
                "source": info.get("extractor_key", domain),
                "quality": quality_preset
            }

            set_cache(cache_key, result)
            return result

    except Exception as e:
        logging.error(f"yt-dlp error: {str(e)}")
        return None

# =========================================================
# ROUTES
# =========================================================

@app.get("/get_media")
async def get_media(url: str, request: Request, quality: str = "720"):

    key = request.headers.get("x-api-key")

    if not key or key not in VALID_API_KEYS:
        raise HTTPException(401, "Unauthorized: Invalid API Key")

    now = time.time()

    user_history = RATE_STORE.get(key, [])
    user_history = [t for t in user_history if now - t < RATE_WINDOW]

    if len(user_history) >= RATE_LIMIT:
        raise HTTPException(429, "Rate limit exceeded")

    user_history.append(now)
    RATE_STORE[key] = user_history

    if not url:
        raise HTTPException(400, "URL is required")

    if "?" in url and ("facebook" in url or "instagram" in url):
        url = url.split("?")[0]

    if not is_valid_url(url):
        raise HTTPException(400, "Unsupported or invalid URL")

    try:
        loop = asyncio.get_event_loop()

        result = await loop.run_in_executor(
            executor,
            extract_media,
            url,
            quality
        )

        if not result:
            raise HTTPException(
                404,
                "Could not extract video. Content may be private or blocked."
            )

        return result

    except HTTPException:
        raise

    except Exception as e:
        logging.error(f"Critical Error: {str(e)}")
        raise HTTPException(500, "Internal server error")

# =========================================================
# RUNNER
# =========================================================

if __name__ == "__main__":
    import uvicorn

    port = int(os.environ.get("PORT", 8000))

    uvicorn.run(
        app,
        host="0.0.0.0",
        port=port
    )