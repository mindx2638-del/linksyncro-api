import random
import yt_dlp
import logging
import time
import asyncio
import hashlib
import os
import re
from threading import Lock
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from urllib.parse import urlparse
from concurrent.futures import ThreadPoolExecutor

# -----------------------------
# APP INITIALIZATION
# -----------------------------
app = FastAPI(title="LinkSyncro Media API", version="4.1")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # ⚠️ production এ domain বসাও
    allow_credentials=True,
    allow_methods=["GET"],
    allow_headers=["*"],
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)

executor = ThreadPoolExecutor(max_workers=10)

# -----------------------------
# CACHE & SETTINGS
# -----------------------------
cache = {}
cache_lock = Lock()

CACHE_TTL = 1200

rate_store = {}
RATE_LIMIT = 60
RATE_WINDOW = 60

VALID_API_KEYS = {"demo_key_123", "premium_key_456"}

COOKIES_DIR = "cookies"

USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64)...",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X)...",
    "Mozilla/5.0 (Linux; Android 11; Pixel 5)...",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)..."
]

ALLOWED_DOMAINS = (
    "youtube.com", "youtu.be",
    "facebook.com", "fb.watch", "fb.com",
    "instagram.com", "tiktok.com"
)

# -----------------------------
# HELPERS
# -----------------------------

def clean_url(url: str):
    """Remove invalid trailing characters like । | space etc"""
    url = url.strip()
    url = re.sub(r"[।.,!?| ]+$", "", url)
    return url


def is_valid_url(url: str):
    try:
        parsed = urlparse(url)
        domain = (parsed.hostname or "").replace("www.", "")

        # FIXED: correct domain validation
        return any(domain == d or domain.endswith("." + d) for d in ALLOWED_DOMAINS)

    except:
        return False


def get_ordered_cookies(site_key: str):
    if not os.path.exists(COOKIES_DIR):
        return []

    files = [
        f for f in os.listdir(COOKIES_DIR)
        if f.startswith(site_key) and f.endswith(".txt")
    ]

    def extract_number(name):
        try:
            return int(name.split("_")[-1].split(".")[0])
        except:
            return 0

    files.sort(key=extract_number)

    return [os.path.join(COOKIES_DIR, f) for f in files]


# -----------------------------
# CORE ENGINE
# -----------------------------
def extract_media(url: str):

    cache_key = hashlib.md5(url.encode()).hexdigest()

    # CACHE CHECK
    with cache_lock:
        if cache_key in cache:
            data, ts = cache[cache_key]
            if time.time() - ts < CACHE_TTL:
                logging.info(f"Cache Hit: {url}")
                return data

    parsed_url = urlparse(url)
    domain = parsed_url.hostname or ""

    site_key, referer = "", ""

    if "instagram.com" in domain:
        site_key, referer = "instagram", "https://www.instagram.com/"
    elif any(x in domain for x in ["facebook.com", "fb.watch", "fb.com"]):
        site_key, referer = "facebook", "https://www.facebook.com/"
    elif any(x in domain for x in ["youtube.com", "youtu.be"]):
        site_key, referer = "youtube", "https://www.youtube.com/"
    elif "tiktok.com" in domain:
        site_key, referer = "tiktok", "https://www.tiktok.com/"

    cookie_list = get_ordered_cookies(site_key) if site_key else []
    if not cookie_list:
        cookie_list = [None]

    for cookie_path in cookie_list:

        ydl_opts = {
            "format": "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best",
            "quiet": True,
            "no_warnings": True,
            "noplaylist": True,
            "socket_timeout": 25,
            "retries": 2,
            "nocheckcertificate": True,
            "geo_bypass": True,
            "user_agent": random.choice(USER_AGENTS),
            "http_headers": {
                "Referer": referer,
                "Accept": "/",   # FIXED
            },
        }

        if cookie_path:
            ydl_opts["cookiefile"] = cookie_path
            logging.info(f"Trying cookie: {cookie_path}")

        if site_key == "instagram":
            ydl_opts["http_headers"].update({
                "Sec-Fetch-Mode": "navigate",
                "Sec-Fetch-Site": "same-origin",
                "Origin": "https://www.instagram.com"
            })

        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)

                download_url = info.get("url")

                if not download_url and "formats" in info:
                    valid_formats = [
                        f for f in info["formats"]
                        if f.get("vcodec") != "none" and f.get("acodec") != "none"
                    ]

                    if not valid_formats:
                        valid_formats = [f for f in info["formats"] if f.get("url")]

                    if valid_formats:
                        valid_formats.sort(
                            key=lambda x: (x.get("height") or 0),
                            reverse=True
                        )
                        download_url = valid_formats[0]["url"]

                if download_url:
                    result = {
                        "status": "success",
                        "url": download_url,
                        "title": info.get("title", "Video"),
                        "thumbnail": info.get("thumbnail"),
                        "duration": info.get("duration"),
                        "source": info.get("extractor_key", domain)
                    }

                    with cache_lock:
                        cache[cache_key] = (result, time.time())

                        if len(cache) > 1000:
                            cache.clear()  # safer

                    return result

        except Exception as e:
            logging.error(f"YT-DLP ERROR ({cookie_path}): {str(e)}")
            continue

    return None


# -----------------------------
# ROUTES
# -----------------------------
@app.get("/get_media")
async def get_media(url: str, request: Request):

    key = request.headers.get("x-api-key")
    if not key or key not in VALID_API_KEYS:
        raise HTTPException(status_code=401, detail="Unauthorized")

    # RATE LIMIT
    now = time.time()
    user_rates = rate_store.get(key, [])

    user_rates = [t for t in user_rates if now - t < RATE_WINDOW]

    if len(user_rates) >= RATE_LIMIT:
        raise HTTPException(status_code=429, detail="Rate limit exceeded")

    user_rates.append(now)
    rate_store[key] = user_rates

    if not url:
        raise HTTPException(status_code=400, detail="URL is required")

    # FIXED URL CLEANING
    url = clean_url(url)

    if "?" in url and ("facebook" in url or "instagram" in url):
        url = url.split("?")[0]

    if not is_valid_url(url):
        raise HTTPException(status_code=400, detail="Invalid URL")

    try:
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(executor, extract_media, url)

        if not result:
            raise HTTPException(
                status_code=404,
                detail="Content blocked or cookies failed"
            )

        return result

    except Exception as e:
        logging.error(f"Server error: {str(e)}")
        raise HTTPException(status_code=500, detail="Server error")


# -----------------------------
# RUN
# -----------------------------
if __name__ == "__main__":
    import uvicorn

    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)