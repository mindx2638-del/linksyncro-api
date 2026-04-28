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

    if cache_key in cache:
        data, ts = cache[cache_key]
        if time.time() - ts < CACHE_TTL:
            return data

    domain = urlparse(url).hostname or ""
    cookie_list = [None] + get_cookie_files(domain)

    output_path = os.path.join(TEMP_DIR, f"{cache_key}.mp4")

    for cookie_path in cookie_list:
        try:
            ydl_opts = {
                # 🔥 BEST HD FIX
                "format": "bv*+ba/best",
                "merge_output_format": "mp4",

                "outtmpl": output_path,

                "quiet": True,
                "no_warnings": True,
                "noplaylist": True,

                "socket_timeout": 60,
                "retries": 15,

                "nocheckcertificate": True,
                "geo_bypass": True,

                "user_agent": random.choice(USER_AGENTS),

                "postprocessors": [
                    {
                        "key": "FFmpegVideoConvertor",
                        "preferedformat": "mp4"
                    }
                ]
            }

            if cookie_path:
                ydl_opts["cookiefile"] = cookie_path

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

            cache[cache_key] = (result, time.time())

            return result

        except Exception as e:
            logging.error(f"Failed: {str(e)}")
            continue

    return None


# -----------------------------
# FILE SERVE
# -----------------------------
@app.get("/file")
def serve_file(filename: str):

    safe_path = os.path.join(TEMP_DIR, os.path.basename(filename))

    if not os.path.exists(safe_path):
        raise HTTPException(status_code=404, detail="File not found")

    return FileResponse(
        safe_path,
        media_type="video/mp4",
        filename="video.mp4"
    )


# -----------------------------
# RUN
# -----------------------------
if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)