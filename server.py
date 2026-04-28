import random
import yt_dlp
import logging
import time
import asyncio
import hashlib
import os

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from urllib.parse import urlparse
from concurrent.futures import ThreadPoolExecutor

# -----------------------------
# APP INITIALIZATION
# -----------------------------
app = FastAPI(title="LinkSyncro Universal API", version="4.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["GET"],
    allow_headers=["*"],
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

executor = ThreadPoolExecutor(max_workers=20)

# -----------------------------
# CACHE & SETTINGS
# -----------------------------
cache = {}
CACHE_TTL = 1200

rate_store = {}
RATE_LIMIT = 50
RATE_WINDOW = 60

VALID_API_KEYS = {"demo_key_123", "premium_key_456"}

TEMP_DIR = "/app/temp"
os.makedirs(TEMP_DIR, exist_ok=True)

# -----------------------------
# USER AGENTS
# -----------------------------
USER_AGENTS = [
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X)",
    "Mozilla/5.0 (Linux; Android 14)",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
]

# -----------------------------
# HELPERS
# -----------------------------
def is_valid_url(url: str):
    try:
        parsed = urlparse(url)
        return parsed.scheme in ["http", "https"] and parsed.hostname
    except:
        return False


def get_cookie_files(domain):
    folder_map = {
        "facebook": "facebook_cookies",
        "fb": "facebook_cookies",
        "youtube": "youtube_cookies",
        "youtu.be": "youtube_cookies",
        "instagram": "instagram_cookies"
    }

    target_folder = ""
    for key, folder in folder_map.items():
        if key in domain:
            target_folder = folder
            break

    if not target_folder:
        return []

    base_path = os.path.join("cookies", target_folder)

    if os.path.exists(base_path):
        files = [
            os.path.join(base_path, f)
            for f in os.listdir(base_path)
            if f.endswith(".txt")
        ]
        files.sort()
        return files

    return []

# -----------------------------
# CORE ENGINE (FIXED)
# -----------------------------
def extract_media(url: str):
    cache_key = hashlib.md5(url.encode()).hexdigest()

    # ✅ CACHE CHECK
    if cache_key in cache:
        data, ts = cache[cache_key]
        if time.time() - ts < CACHE_TTL:
            logging.info(f"Cache Hit: {url}")
            return data

    domain = urlparse(url).hostname or ""
    cookie_list = [None] + get_cookie_files(domain)

    for cookie_path in cookie_list:
        try:
            output_path = f"{TEMP_DIR}/{cache_key}.mp4"

            # already downloaded হলে reuse
            if os.path.exists(output_path):
                return {
                    "status": "success",
                    "file": output_path,
                    "source": domain
                }

            ydl_opts = {
                # 🔥 HD + AUDIO FIX
                "format": "bestvideo+bestaudio/best",
                "outtmpl": output_path,
                "merge_output_format": "mp4",

                "quiet": True,
                "no_warnings": True,
                "noplaylist": True,
                "socket_timeout": 45,
                "retries": 10,
                "nocheckcertificate": True,
                "geo_bypass": True,

                "user_agent": random.choice(USER_AGENTS),

                "http_headers": {
                    "Referer": "https://www.google.com/"
                }
            }

            if cookie_path:
                ydl_opts["cookiefile"] = cookie_path
                logging.info(f"Using cookie: {cookie_path}")

            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)

                result = {
                    "status": "success",
                    "file": output_path,
                    "title": info.get("title"),
                    "thumbnail": info.get("thumbnail"),
                    "duration": info.get("duration"),
                    "source": info.get("extractor_key", domain)
                }

                # cache store
                cache[cache_key] = (result, time.time())
                if len(cache) > 2000:
                    cache.pop(next(iter(cache)))

                return result

        except Exception as e:
            logging.error(f"Failed attempt: {str(e)}")
            continue

    return None


# -----------------------------
# ROUTES
# -----------------------------
@app.get("/get_media")
async def get_media(url: str, request: Request):

    # API KEY CHECK
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

    # URL VALIDATION
    if not url:
        raise HTTPException(status_code=400, detail="URL required")

    if "?" in url and ("facebook" in url or "instagram" in url):
        url = url.split("?")[0]

    if not is_valid_url(url):
        raise HTTPException(status_code=400, detail="Invalid URL")

    # EXECUTE
    loop = asyncio.get_event_loop()
    result = await loop.run_in_executor(executor, extract_media, url)

    if not result:
        raise HTTPException(status_code=404, detail="Extraction failed")

    return result


# -----------------------------
# FILE SERVE
# -----------------------------
@app.get("/file")
def serve_file(path: str):

    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail="File not found")

    return FileResponse(
        path,
        media_type="video/mp4",
        filename=os.path.basename(path)
    )


# -----------------------------
# RUN
# -----------------------------
if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)