import random
import yt_dlp
import logging
import time
import asyncio
import hashlib
import os
import threading

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from urllib.parse import urlparse
from concurrent.futures import ThreadPoolExecutor

# -----------------------------
# APP INITIALIZATION
# -----------------------------
app = FastAPI(title="LinkSyncro Media API", version="2.0")

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

executor = ThreadPoolExecutor(max_workers=20)

# -----------------------------
# CACHE & SETTINGS
# -----------------------------
cache = {}
cache_lock = threading.Lock()

CACHE_TTL = 1200  # 20 min

rate_store = {}
RATE_LIMIT = 50
RATE_WINDOW = 60

VALID_API_KEYS = {"demo_key_123", "premium_key_456"}

USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/123.0.0.0 Safari/537.36",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) Version/17.4 Mobile Safari/604.1",
    "Mozilla/5.0 (Linux; Android 11) Chrome/90.0 Mobile Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/122.0.0.0 Safari/537.36"
]

# -----------------------------
# HELPERS
# -----------------------------
def is_valid_url(url: str):
    try:
        parsed = urlparse(url)
        if parsed.scheme not in ["http", "https"] or not parsed.hostname:
            return False

        domain = parsed.hostname.replace("www.", "")
        allowed = [
            "youtube.com", "youtu.be",
            "facebook.com", "fb.watch", "fb.com",
            "instagram.com",
            "tiktok.com",
            "twitter.com", "x.com"
        ]

        return any(d in domain for d in allowed)
    except:
        return False

# -----------------------------
# CORE ENGINE
# -----------------------------
def extract_media(url: str):

    cache_key = hashlib.md5(url.encode()).hexdigest()

    # -----------------------------
    # CACHE CHECK
    # -----------------------------
    with cache_lock:
        if cache_key in cache:
            data, ts = cache[cache_key]
            if time.time() - ts < CACHE_TTL:
                logging.info(f"Cache Hit: {url}")
                return data

    # -----------------------------
    # COOKIES
    # -----------------------------
    fb_cookies = "facebook_cookies.txt"
    yt_cookies = "youtube_cookies.txt"
    ig_cookies = "instagram_cookies.txt"
    tt_cookies = "tiktok_cookies.txt"
    tw_cookies = "twitter_cookies.txt"

    domain = urlparse(url).hostname or ""

    # -----------------------------
    # YT-DLP CONFIG (FIXED)
    # -----------------------------
    ydl_opts = {
        "format": "best[ext=mp4]/best",
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "socket_timeout": 60,
        "retries": 10,
        "nocheckcertificate": True,
        "geo_bypass": True,
        "user_agent": random.choice(USER_AGENTS),
        "http_headers": {
            "Accept": "*/*",
            "Referer": "https://www.google.com/",
        },
        "extractor_args": {
            "youtube": {
                "player_client": ["android", "ios", "web"]
            },
            "tiktok": {
                "api_hostname": "api16-normal-c-useast1a.tiktokv.com"
            }
        }
    }

    # -----------------------------
    # COOKIE ASSIGNMENT
    # -----------------------------
    if any(d in domain for d in ["facebook.com", "fb.watch", "fb.com"]):
        if os.path.exists(fb_cookies):
            ydl_opts["cookiefile"] = fb_cookies

    elif any(d in domain for d in ["youtube.com", "youtu.be"]):
        if os.path.exists(yt_cookies):
            ydl_opts["cookiefile"] = yt_cookies

    elif "instagram.com" in domain:
        if os.path.exists(ig_cookies):
            ydl_opts["cookiefile"] = ig_cookies

    elif "tiktok.com" in domain:
        if os.path.exists(tt_cookies):
            ydl_opts["cookiefile"] = tt_cookies
            logging.info("TikTok cookies loaded")

        # TikTok stability mode
        ydl_opts["format"] = "best"

    elif any(d in domain for d in ["twitter.com", "x.com"]):
        if os.path.exists(tw_cookies):
            ydl_opts["cookiefile"] = tw_cookies
            logging.info("Twitter cookies loaded")

        # Twitter stability mode
        ydl_opts["format"] = "best"

    # -----------------------------
    # EXTRACTION
    # -----------------------------
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)

            download_url = info.get("url")

            # fallback format selection (FIXED)
            if not download_url:
                formats = info.get("formats", [])

                valid_formats = [
                    f for f in formats
                    if f.get("url")
                ]

                if valid_formats:
                    valid_formats.sort(
                        key=lambda x: (
                            x.get("height") or 0,
                            x.get("tbr") or 0
                        ),
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
                "source": info.get("extractor_key", domain)
            }

            # -----------------------------
            # CACHE SAVE (thread safe)
            # -----------------------------
            with cache_lock:
                cache[cache_key] = (result, time.time())

                if len(cache) > 1000:
                    cache.pop(next(iter(cache)))

            return result

    except Exception as e:
        logging.error(f"yt-dlp error: {str(e)}")
        return None

# -----------------------------
# ROUTE
# -----------------------------
@app.get("/get_media")
async def get_media(url: str, request: Request):

    # API KEY
    key = request.headers.get("x-api-key")
    if not key or key not in VALID_API_KEYS:
        raise HTTPException(status_code=401, detail="Invalid API Key")

    # RATE LIMIT
    now = time.time()
    user_rates = rate_store.get(key, [])
    user_rates = [t for t in user_rates if now - t < RATE_WINDOW]

    if len(user_rates) >= RATE_LIMIT:
        raise HTTPException(status_code=429, detail="Rate limit exceeded")

    user_rates.append(now)
    rate_store[key] = user_rates

    # URL CHECK
    if not url:
        raise HTTPException(status_code=400, detail="URL required")

    if "?" in url and ("facebook" in url or "instagram" in url):
        url = url.split("?")[0]

    if not is_valid_url(url):
        raise HTTPException(status_code=400, detail="Invalid URL")

    # EXECUTION
    try:
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(executor, extract_media, url)

        if not result:
            raise HTTPException(
                status_code=404,
                detail="Could not extract media (private/restricted)"
            )

        return result

    except HTTPException as e:
        raise e
    except Exception as e:
        logging.error(f"Server error: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal error")

# -----------------------------
# RUNNER
# -----------------------------
if __name__ == "__main__":
    import uvicorn

    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)