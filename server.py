import os
import time
import random
import hashlib
import logging
import asyncio
import yt_dlp

from collections import OrderedDict, defaultdict, deque
from urllib.parse import urlparse
from concurrent.futures import ThreadPoolExecutor

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware

# -----------------------------
# APP INIT (PRODUCTION READY)
# -----------------------------
app = FastAPI(
    title="LinkSyncro Universal Media API",
    version="5.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# -----------------------------
# LOGGING (PRO LEVEL)
# -----------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s"
)

# -----------------------------
# EXECUTOR (HIGH LOAD READY)
# -----------------------------
executor = ThreadPoolExecutor(max_workers=30)

# -----------------------------
# CONFIG
# -----------------------------
CACHE_TTL = 1200  # 20 min
MAX_CACHE_SIZE = 1500

RATE_LIMIT = 80
RATE_WINDOW = 60  # seconds

VALID_API_KEYS = {
    "demo_key_123",
    "premium_key_456"
}

USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124 Safari/537.36",
    "Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4) AppleWebKit/605.1.15 Version/17 Safari/604.1"
]

# -----------------------------
# THREAD SAFE CACHE
# -----------------------------
cache = OrderedDict()
rate_store = defaultdict(deque)

# -----------------------------
# CACHE FUNCTIONS (LRU + TTL)
# -----------------------------
def cache_get(key):
    item = cache.get(key)
    if not item:
        return None

    data, ts = item
    if time.time() - ts > CACHE_TTL:
        cache.pop(key, None)
        return None

    # refresh order (LRU)
    cache.move_to_end(key)
    return data

def cache_set(key, value):
    if key in cache:
        cache.move_to_end(key)

    cache[key] = (value, time.time())

    if len(cache) > MAX_CACHE_SIZE:
        cache.popitem(last=False)

# -----------------------------
# URL VALIDATION
# -----------------------------
def is_valid_url(url: str):
    try:
        p = urlparse(url)
        return p.scheme in ("http", "https") and bool(p.netloc)
    except:
        return False

# -----------------------------
# RATE LIMIT (SLIDING WINDOW)
# -----------------------------
def check_rate(key: str) -> bool:
    now = time.time()
    q = rate_store[key]

    while q and now - q[0] > RATE_WINDOW:
        q.popleft()

    if len(q) >= RATE_LIMIT:
        return False

    q.append(now)
    return True

# -----------------------------
# CORE ENGINE (YT-DLP POWERED)
# -----------------------------
def extract_media(url: str):
    cache_key = hashlib.md5(url.encode()).hexdigest()

    cached = cache_get(cache_key)
    if cached:
        logging.info("CACHE HIT")
        return cached

    ydl_opts = {
        "format": "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best",
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "retries": 5,
        "socket_timeout": 50,
        "geo_bypass": True,
        "nocheckcertificate": True,
        "user_agent": random.choice(USER_AGENTS),
        "http_headers": {
            "Accept": "*/*",
            "Accept-Language": "en-US,en;q=0.9",
        },
        "extractor_args": {
            "youtube": {
                "player_client": ["android", "web"]
            }
        }
    }

    # cookies support (optional)
    if os.path.exists("cookies.txt"):
        ydl_opts["cookiefile"] = "cookies.txt"

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)

            download_url = info.get("url")

            # fallback smart format selection
            if not download_url:
                formats = info.get("formats", [])

                best = None
                for f in formats:
                    if not f.get("url"):
                        continue

                    if f.get("vcodec") == "none" and f.get("acodec") == "none":
                        continue

                    score = f.get("height") or 0

                    if not best or score > (best.get("height") or 0):
                        best = f

                if best:
                    download_url = best.get("url")

            if not download_url:
                return None

            result = {
                "status": "success",
                "url": download_url,
                "title": info.get("title", "Unknown"),
                "thumbnail": info.get("thumbnail"),
                "duration": info.get("duration"),
                "source": info.get("extractor_key", "unknown")
            }

            cache_set(cache_key, result)

            return result

    except Exception as e:
        logging.error(f"EXTRACT ERROR: {str(e)}")
        return None

# -----------------------------
# CLEAN FACEBOOK / INSTAGRAM URL
# -----------------------------
def clean_url(url: str):
    if "?" in url:
        domain = urlparse(url).hostname or ""
        if any(x in domain for x in ["facebook.com", "instagram.com", "fb.watch"]):
            return url.split("?")[0]
    return url

# -----------------------------
# API ROUTE
# -----------------------------
@app.get("/get_media")
async def get_media(url: str, request: Request):

    api_key = request.headers.get("x-api-key")

    if not api_key or api_key not in VALID_API_KEYS:
        raise HTTPException(status_code=401, detail="Invalid API Key")

    if not check_rate(api_key):
        raise HTTPException(status_code=429, detail="Rate limit exceeded")

    if not url:
        raise HTTPException(status_code=400, detail="URL required")

    if not is_valid_url(url):
        raise HTTPException(status_code=400, detail="Invalid URL")

    url = clean_url(url)

    try:
        loop = asyncio.get_event_loop()

        result = await loop.run_in_executor(
            executor,
            extract_media,
            url
        )

        if not result:
            raise HTTPException(
                status_code=404,
                detail="Media not found or private content"
            )

        return result

    except Exception as e:
        logging.error(f"FATAL ERROR: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")

# -----------------------------
# HEALTH CHECK (Render friendly)
# -----------------------------
@app.get("/")
def root():
    return {
        "status": "running",
        "service": "LinkSyncro API v5.0"
    }

# -----------------------------
# RUNNER (PRODUCTION)
# -----------------------------
if __name__ == "__main__":
    import uvicorn

    port = int(os.environ.get("PORT", 8000))

    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=port,
        workers=1,
        log_level="info"
    )