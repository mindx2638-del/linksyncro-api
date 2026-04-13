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

# -----------------------------
# APP INITIALIZATION
# -----------------------------
app = FastAPI(title="LinkSyncro Media API", version="3.0")

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

USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/123.0.0.0 Safari/537.36",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 Version/17.4 Mobile Safari/604.1",
    "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 Chrome/90.0.4430.91 Mobile Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/122.0.0.0 Safari/537.36"
]

# -----------------------------
# HELPERS
# -----------------------------
def is_valid_url(url: str):
    try:
        parsed = urlparse(url)
        if parsed.scheme not in ["http", "https"] or not parsed.hostname:
            return False
        domain = parsed.hostname.lower().replace("www.", "")
        allowed = [
            "youtube.com", "youtu.be",
            "facebook.com", "fb.watch", "fb.com",
            "instagram.com",
            "tiktok.com", "vt.tiktok.com", "vm.tiktok.com"
        ]
        return any(domain.endswith(d) for d in allowed)
    except:
        return False

def get_cookie_files(domain):
    folder_map = {
        "facebook": "facebook_cookies",
        "fb": "facebook_cookies",
        "youtube": "youtube_cookies",
        "youtu.be": "youtube_cookies",
        "instagram": "instagram_cookies",
        "tiktok": "tiktok_cookies",
        "vt.tiktok": "tiktok_cookies",
        "vm.tiktok": "tiktok_cookies"
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
        files = [os.path.join(base_path, f) for f in os.listdir(base_path) if f.endswith(".txt")]
        files.sort()
        return files
    return []

# -----------------------------
# CORE ENGINE
# -----------------------------
def extract_media(url: str):

    cache_key = hashlib.md5(url.encode()).hexdigest()
    if cache_key in cache:
        data, ts = cache[cache_key]
        if time.time() - ts < CACHE_TTL:
            logging.info(f"Cache Hit: {url}")
            return data

    domain = urlparse(url).hostname or ""
    is_tiktok = "tiktok.com" in domain

    cookie_list = [None]
    cookie_list.extend(get_cookie_files(domain))

    for cookie_path in cookie_list:

        ydl_opts = {
            "format": "best" if is_tiktok else "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best",
            "quiet": True,
            "no_warnings": True,
            "noplaylist": True,
            "socket_timeout": 30,
            "retries": 3,
            "nocheckcertificate": True,
            "geo_bypass": True,
            "user_agent": random.choice(USER_AGENTS),

            "http_headers": {
                "User-Agent": random.choice(USER_AGENTS),
                "Accept": "*/*",
                "Referer": "https://www.tiktok.com/" if is_tiktok else "https://www.google.com/",
                "Origin": "https://www.tiktok.com" if is_tiktok else "",
            },

            "extractor_args": {
                "youtube": {"player_client": ["android", "ios", "mweb"]},
                "instagram": {"force_subtitles": False},
                "facebook": {"force_generic_extractor": False},
                "tiktok": {
                    "app_name": "musical_ly",
                    "device_id": "1234567890"
                }
            }
        }

        if cookie_path:
            ydl_opts["cookiefile"] = cookie_path
            logging.info(f"Trying with cookie: {cookie_path}")
        else:
            logging.info(f"Trying WITHOUT cookies")

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
                        valid_formats.sort(key=lambda x: (x.get("height") or 0), reverse=True)
                        download_url = valid_formats[0]["url"]

                print("DOWNLOAD URL:", download_url)

                if download_url:
                    result = {
                        "status": "success",
                        "url": download_url,
                        "title": info.get("title", "Video"),
                        "thumbnail": info.get("thumbnail"),
                        "duration": info.get("duration"),
                        "source": info.get("extractor_key", domain)
                    }

                    cache[cache_key] = (result, time.time())
                    if len(cache) > 1000:
                        cache.pop(next(iter(cache)))

                    return result

        except Exception as e:
            logging.warning(f"Failed attempt: {str(e)}")
            continue

    return None

# -----------------------------
# ROUTES
# -----------------------------
@app.get("/get_media")
async def get_media(url: str, request: Request):

    key = request.headers.get("x-api-key")
    if not key or key not in VALID_API_KEYS:
        raise HTTPException(status_code=401, detail="Invalid API Key")

    now = time.time()
    user_rates = rate_store.get(key, [])
    user_rates = [t for t in user_rates if now - t < RATE_WINDOW]
    rate_store[key] = user_rates

    if len(user_rates) >= RATE_LIMIT:
        raise HTTPException(status_code=429, detail="Rate limit exceeded")

    rate_store[key].append(now)

    if not url:
        raise HTTPException(status_code=400, detail="URL required")

    if "?" in url and any(x in url for x in ["facebook", "fb", "instagram"]):
        url = url.split("?")[0]

    if not is_valid_url(url):
        raise HTTPException(status_code=400, detail="Invalid URL")

    try:
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(executor, extract_media, url)

        if not result:
            raise HTTPException(status_code=404, detail="Extraction failed")

        return result

    except HTTPException as he:
        raise he

    except Exception as e:
        logging.error(f"Critical Error: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")

# -----------------------------
# RUNNER
# -----------------------------
if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)