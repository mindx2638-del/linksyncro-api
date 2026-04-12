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
# APP INIT
# -----------------------------
app = FastAPI(title="LinkSyncro Media API", version="5.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["GET"],
    allow_headers=["*"],
)

logging.basicConfig(level=logging.INFO)

executor = ThreadPoolExecutor(max_workers=10)

# -----------------------------
# SETTINGS
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
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
    "Mozilla/5.0 (Linux; Android 11)",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X)"
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
    url = url.strip()
    url = re.sub(r"[।.,!?|—\s\u200b\u200c\u200d]+$", "", url)
    return url


def is_valid_url(url: str):
    try:
        domain = (urlparse(url).hostname or "").replace("www.", "")
        return any(domain == d or domain.endswith("." + d) for d in ALLOWED_DOMAINS)
    except:
        return False


def get_cookies(site):
    if not os.path.exists(COOKIES_DIR):
        return []

    files = [
        os.path.join(COOKIES_DIR, f)
        for f in os.listdir(COOKIES_DIR)
        if f.startswith(site)
    ]
    return files if files else [None]


# -----------------------------
# CORE
# -----------------------------
def extract_media(url: str):

    cache_key = hashlib.md5(url.encode()).hexdigest()

    # CACHE
    with cache_lock:
        if cache_key in cache:
            data, ts = cache[cache_key]
            if time.time() - ts < CACHE_TTL:
                return data

    domain = urlparse(url).hostname or ""

    site, referer = "", ""

    if "facebook" in domain or "fb.watch" in domain:
        site = "facebook"
        referer = "https://www.facebook.com/"
    elif "instagram" in domain:
        site = "instagram"
        referer = "https://www.instagram.com/"
    elif "youtube" in domain or "youtu.be" in domain:
        site = "youtube"
        referer = "https://www.youtube.com/"
    elif "tiktok" in domain:
        site = "tiktok"
        referer = "https://www.tiktok.com/"

    cookies = get_cookies(site)

    for cookie in cookies:

        ydl_opts = {
            "quiet": True,
            "noplaylist": True,
            "retries": 2,
            "socket_timeout": 25,
            "geo_bypass": True,
            "nocheckcertificate": True,
            "user_agent": random.choice(USER_AGENTS),
            "http_headers": {
                "Referer": referer,
                "Accept-Language": "en-US,en;q=0.9",
            },
        }

        if cookie:
            ydl_opts["cookiefile"] = cookie

        # 🔥 FACEBOOK FIX
        if site == "facebook":
            ydl_opts["http_headers"].update({
                "Origin": "https://www.facebook.com",
                "Sec-Fetch-Site": "same-origin",
                "Sec-Fetch-Mode": "navigate",
            })

        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)

                # 🔥 BEST URL FIX
                download_url = info.get("url")

                if not download_url:
                    formats = info.get("formats", [])
                    formats = [f for f in formats if f.get("url")]

                    if formats:
                        formats.sort(key=lambda x: x.get("height", 0), reverse=True)
                        download_url = formats[0]["url"]

                if download_url:
                    result = {
                        "status": "success",
                        "url": download_url,
                        "title": info.get("title"),
                        "thumbnail": info.get("thumbnail"),
                        "duration": info.get("duration"),
                        "source": site
                    }

                    with cache_lock:
                        cache[cache_key] = (result, time.time())

                    return result

        except Exception as e:
            logging.error(f"ERROR: {e}")
            continue

    return None


# -----------------------------
# ROUTE
# -----------------------------
@app.get("/get_media")
async def get_media(url: str, request: Request):

    key = request.headers.get("x-api-key")
    if key not in VALID_API_KEYS:
        raise HTTPException(401, "Unauthorized")

    # RATE LIMIT
    now = time.time()
    user = rate_store.get(key, [])
    user = [t for t in user if now - t < RATE_WINDOW]

    if len(user) >= RATE_LIMIT:
        raise HTTPException(429, "Rate limit exceeded")

    user.append(now)
    rate_store[key] = user

    if not url:
        raise HTTPException(400, "URL required")

    url = clean_url(url)

    # 🔥 Facebook clean
    if "facebook" in url and "?" in url:
        url = url.split("?")[0]

    if not is_valid_url(url):
        raise HTTPException(400, "Invalid URL")

    loop = asyncio.get_event_loop()
    result = await loop.run_in_executor(executor, extract_media, url)

    if not result:
        raise HTTPException(404, "Failed (cookies needed)")

    return result


# -----------------------------
# RUN
# -----------------------------
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)