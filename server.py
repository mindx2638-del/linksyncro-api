from fastapi import FastAPI, HTTPException, Request, Depends
from fastapi.middleware.cors import CORSMiddleware
import yt_dlp
import logging
import time
import ipaddress
import asyncio
import hashlib
from urllib.parse import urlparse
from concurrent.futures import ThreadPoolExecutor

app = FastAPI()

# -----------------------------
# CORS (PRODUCTION SAFE)
# -----------------------------
app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://yourdomain.com"],  # ❗ change this
    allow_credentials=True,
    allow_methods=["GET"],
    allow_headers=["*"],
)

# -----------------------------
# LOGGING
# -----------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)

# -----------------------------
# THREAD POOL
# -----------------------------
executor = ThreadPoolExecutor(max_workers=10)

# -----------------------------
# SIMPLE REDIS-LIKE CACHE (replace with real Redis in production)
# -----------------------------
cache = {}
CACHE_TTL = 300

# -----------------------------
# API KEY SYSTEM (ENTERPRISE SECURITY)
# -----------------------------
VALID_API_KEYS = {
    "demo_key_123",
    "premium_key_456"
}

# -----------------------------
# RATE LIMIT PER API KEY
# -----------------------------
rate_store = {}
RATE_LIMIT = 20
RATE_WINDOW = 60

# -----------------------------
# ALLOWED DOMAINS (STRICT)
# -----------------------------
ALLOWED_DOMAINS = {
    "youtube.com",
    "www.youtube.com",
    "youtu.be",
    "m.youtube.com"
}

# -----------------------------
# SSRF SAFE CHECK
# -----------------------------
def is_private_ip(host):
    try:
        return ipaddress.ip_address(host).is_private
    except:
        return False


def is_valid_url(url: str):
    try:
        parsed = urlparse(url)

        if parsed.scheme not in ["http", "https"]:
            return False

        if not parsed.hostname:
            return False

        if parsed.hostname in ["localhost", "127.0.0.1"]:
            return False

        if is_private_ip(parsed.hostname):
            return False

        # strict allow list
        if parsed.hostname not in ALLOWED_DOMAINS:
            return False

        return True

    except:
        return False


# -----------------------------
# API KEY VALIDATION
# -----------------------------
def verify_api_key(request: Request):
    key = request.headers.get("x-api-key")

    if not key or key not in VALID_API_KEYS:
        raise HTTPException(status_code=401, detail="Invalid API Key")

    return key


# -----------------------------
# RATE LIMIT PER KEY
# -----------------------------
def check_rate_limit(api_key: str):
    now = time.time()

    if api_key not in rate_store:
        rate_store[api_key] = []

    rate_store[api_key] = [
        t for t in rate_store[api_key]
        if now - t < RATE_WINDOW
    ]

    if len(rate_store[api_key]) >= RATE_LIMIT:
        return False

    rate_store[api_key].append(now)
    return True


# -----------------------------
# CORE YT-DLP ENGINE
# -----------------------------
def extract_video(url: str):

    cache_key = hashlib.md5(url.encode()).hexdigest()

    if cache_key in cache:
        data, ts = cache[cache_key]
        if time.time() - ts < CACHE_TTL:
            return data

    ydl_opts = {
        "format": "bestvideo+bestaudio/best",
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "socket_timeout": 10,
        "retries": 2,
        "user_agent": "Mozilla/5.0",
    }

    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(url, download=False)

        download_url = info.get("url")

        if not download_url and "formats" in info:
            formats = [
                f for f in info["formats"]
                if f.get("url") and f.get("vcodec") != "none"
            ]

            formats.sort(
                key=lambda x: (x.get("height") or 0, x.get("tbr") or 0),
                reverse=True
            )

            if formats:
                download_url = formats[0]["url"]

        result = {
            "status": "success",
            "url": download_url,
            "title": info.get("title"),
            "thumbnail": info.get("thumbnail"),
            "duration": info.get("duration"),
            "source": info.get("extractor")
        }

        cache[cache_key] = (result, time.time())

        return result


# -----------------------------
# MAIN API
# -----------------------------
@app.get("/get_video")
async def get_video(url: str, request: Request):

    api_key = verify_api_key(request)

    # RATE LIMIT CHECK
    if not check_rate_limit(api_key):
        raise HTTPException(status_code=429, detail="Rate limit exceeded")

    if not url:
        raise HTTPException(status_code=400, detail="URL required")

    if not is_valid_url(url):
        raise HTTPException(status_code=400, detail="Unsafe URL detected")

    try:
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(executor, extract_video, url)

        if not result:
            raise HTTPException(status_code=404, detail="Video not found")

        logging.info(f"API Success: {result.get('title')} | Key: {api_key}")

        return result

    except Exception as e:
        logging.error(str(e))
        raise HTTPException(status_code=500, detail="Internal server error")