import random
import yt_dlp
import logging
import time
import asyncio
import hashlib
import os

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from urllib.parse import urlparse
from concurrent.futures import ThreadPoolExecutor
from collections import OrderedDict
from threading import Lock

# -----------------------------
# APP INIT
# -----------------------------
app = FastAPI(title="LinkSyncro Universal API", version="3.2")

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

# -----------------------------
# PERFORMANCE
# -----------------------------
MAX_WORKERS = min(32, (os.cpu_count() or 1) * 2)
executor = ThreadPoolExecutor(max_workers=MAX_WORKERS)

# -----------------------------
# CACHE (THREAD SAFE LRU)
# -----------------------------
cache = OrderedDict()
cache_lock = Lock()

CACHE_TTL = 1200
CACHE_MAX_SIZE = 2000

# -----------------------------
# RATE LIMIT (THREAD SAFE)
# -----------------------------
rate_store = {}
rate_lock = Lock()

RATE_LIMIT = 50
RATE_WINDOW = 60

# -----------------------------
# SECURITY
# -----------------------------
VALID_API_KEYS = {"demo_key_123", "premium_key_456"}

# -----------------------------
# USER AGENTS
# -----------------------------
USER_AGENTS = [
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X)",
    "Mozilla/5.0 (Linux; Android 14; Pixel Build/ABC)",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
]

# -----------------------------
# HELPERS
# -----------------------------
def is_valid_url(url: str) -> bool:
    try:
        parsed = urlparse(url)
        blocked = ["file", "ftp", "data"]

        return (
            parsed.scheme in ["http", "https"]
            and parsed.hostname is not None
            and parsed.scheme not in blocked
        )
    except Exception:
        return False


def get_cookie_files(domain: str):
    folder_map = {
        "facebook": "facebook_cookies",
        "fb": "facebook_cookies",
        "youtube": "youtube_cookies",
        "youtu.be": "youtube_cookies",
        "instagram": "instagram_cookies",
        "tiktok": "tiktok_cookies"
    }

    target_folder = None

    for key, folder in folder_map.items():
        if key in domain:
            target_folder = folder
            break

    if not target_folder:
        return []

    base_path = os.path.join("cookies", target_folder)

    if not os.path.exists(base_path):
        return []

    return sorted(
        os.path.join(base_path, f)
        for f in os.listdir(base_path)
        if f.endswith(".txt")
    )

# -----------------------------
# CORE ENGINE
# -----------------------------
def extract_media(url: str):
    cache_key = hashlib.md5(url.encode()).hexdigest()

    # ---------------- CACHE CHECK ----------------
    with cache_lock:
        if cache_key in cache:
            data, ts = cache[cache_key]

            if time.time() - ts < CACHE_TTL:
                cache.move_to_end(cache_key)
                logging.info("Cache Hit")
                return data

    domain = urlparse(url).hostname or ""
    cookie_list = [None] + get_cookie_files(domain)

    for cookie_path in cookie_list:

        ydl_opts = {
            "format": "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
            "quiet": True,
            "no_warnings": True,
            "noplaylist": True,
            "socket_timeout": 30,
            "retries": 3,
            "nocheckcertificate": True,
            "geo_bypass": True,
            "user_agent": random.choice(USER_AGENTS),
            "concurrent_fragment_downloads": 2,
            "ignoreerrors": True,
            "http_headers": {
                "Accept": "/",
                "Accept-Language": "en-US,en;q=0.5",
                "Referer": url
            },
            "extractor_args": {
                "youtube": {
                    "player_client": ["android", "ios", "mweb", "tv"],
                    "player_skip": ["configs"]
                }
            }
        }

        if cookie_path:
            ydl_opts["cookiefile"] = cookie_path

        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)

                if not info:
                    continue

                if "entries" in info:
                    info = info["entries"][0]

                download_url = info.get("url")

                if not download_url and "formats" in info:
                    formats = [
                        f for f in info["formats"]
                        if f.get("url") and f.get("vcodec") != "none"
                    ]

                    if formats:
                        formats.sort(
                            key=lambda x: (x.get("height") or 0),
                            reverse=True
                        )
                        download_url = formats[0]["url"]

                if download_url:
                    result = {
                        "status": "success",
                        "url": download_url,
                        "title": info.get("title"),
                        "thumbnail": info.get("thumbnail"),
                        "duration": info.get("duration"),
                        "source": info.get("extractor_key", domain),
                        "ext": info.get("ext", "mp4")
                    }

                    # ---------------- CACHE SAVE ----------------
                    with cache_lock:
                        cache[cache_key] = (result, time.time())
                        cache.move_to_end(cache_key)

                        if len(cache) > CACHE_MAX_SIZE:
                            cache.popitem(last=False)

                    return result

        except Exception as e:
            logging.warning(f"Attempt failed: {str(e)}")
            continue

    return None

# -----------------------------
# RATE LIMIT CHECK
# -----------------------------
def check_rate_limit(key: str) -> bool:
    now = time.time()

    with rate_lock:
        history = rate_store.get(key, [])
        history = [t for t in history if now - t < RATE_WINDOW]

        if len(history) >= RATE_LIMIT:
            return False

        history.append(now)
        rate_store[key] = history

    return True

# -----------------------------
# ROUTE
# -----------------------------
@app.get("/get_media")
async def get_media(url: str, request: Request):

    key = request.headers.get("x-api-key")

    if key not in VALID_API_KEYS:
        raise HTTPException(status_code=401, detail="Invalid API Key")

    if not check_rate_limit(key):
        raise HTTPException(status_code=429, detail="Rate limit exceeded")

    if not url:
        raise HTTPException(status_code=400, detail="URL required")

    if any(x in url for x in ["facebook", "instagram", "fb"]):
        url = url.split("?")[0]

    if not is_valid_url(url):
        raise HTTPException(status_code=400, detail="Invalid URL")

    try:
        result = await asyncio.to_thread(extract_media, url)

        if not result:
            raise HTTPException(status_code=404, detail="Could not extract media")

        return result

    except HTTPException:
        raise
    except Exception as e:
        logging.error(f"Critical error: {e}")
        raise HTTPException(status_code=500, detail="Server error")

# -----------------------------
# RUNNER
# -----------------------------
if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        app,
        host="0.0.0.0",
        port=int(os.environ.get("PORT", 8000))
    )
