import random
import yt_dlp
import logging
import time
import hashlib
import os
import asyncio
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from urllib.parse import urlparse
from concurrent.futures import ThreadPoolExecutor

# -----------------------------
# APP INITIALIZATION
# -----------------------------
app = FastAPI(title="LinkSyncro Pro API", version="5.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["GET"],
    allow_headers=["*"],
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
executor = ThreadPoolExecutor(max_workers=25)

# -----------------------------
# SETTINGS
# -----------------------------
cache = {}
CACHE_TTL = 1800 
VALID_API_KEYS = {"demo_key_123", "premium_key_456"}

USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1"
]

# -----------------------------
# CORE ENGINE (The Magic)
# -----------------------------
def extract_media(url: str):
    cache_key = hashlib.md5(url.encode()).hexdigest()
    if cache_key in cache:
        data, ts = cache[cache_key]
        if time.time() - ts < CACHE_TTL:
            return data

    # ইউটিউব ব্লকিং এড়াতে বিশেষ extractor_args
    ydl_opts = {
        "format": "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "geo_bypass": True,
        "nocheckcertificate": True,
        "socket_timeout": 30,
        "retries": 10,
        "user_agent": random.choice(USER_AGENTS),
        # ইউটিউব এবং টিকটক এর জন্য এই অংশটি খুব গুরুত্বপূর্ণ
        "extractor_args": {
            "youtube": {
                "player_client": ["android", "ios", "mweb"],
                "player_skip": ["webpage", "configs"]
            },
            "tiktok": {
                "app_name": "musical_ly",
                "is_test": False
            }
        },
        "http_headers": {
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
            "Referer": "https://www.google.com/",
        }
    }

    # Cookies Check
    if os.path.exists("cookies.txt"):
        ydl_opts["cookiefile"] = "cookies.txt"
        logging.info(f"Using cookies.txt for: {url}")

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)
            
            # মেটাডাটা এবং ভিডিও ইউআরএল বের করা
            download_url = info.get("url")
            
            # যদি সরাসরি ইউআরএল না থাকে (Formats চেক করা)
            if not download_url and "formats" in info:
                # অডিও এবং ভিডিও দুটোই আছে এমন ফরম্যাট খোঁজা (720p প্রায়োরিটি)
                valid_formats = [f for f in info["formats"] if f.get("vcodec") != "none" and f.get("acodec") != "none" and f.get("url")]
                if not valid_formats:
                    valid_formats = [f for f in info["formats"] if f.get("url")]
                
                if valid_formats:
                    valid_formats.sort(key=lambda x: (x.get("height") or 0), reverse=True)
                    download_url = valid_formats[0]["url"]

            if not download_url:
                return None

            result = {
                "status": "success",
                "url": download_url,
                "title": info.get("title", "Video"),
                "thumbnail": info.get("thumbnail"),
                "duration": info.get("duration"),
                "source": info.get("extractor_key", "Social Media")
            }

            cache[cache_key] = (result, time.time())
            return result

    except Exception as e:
        logging.error(f"yt-dlp error: {str(e)}")
        return None

# -----------------------------
# ROUTES
# -----------------------------
@app.get("/get_media")
async def get_media(url: str, request: Request):
    api_key = request.headers.get("x-api-key")
    if not api_key or api_key not in VALID_API_KEYS:
        raise HTTPException(status_code=401, detail="Unauthorized")

    if not url:
        raise HTTPException(status_code=400, detail="URL required")

    # URL Clean up
    parsed_url = urlparse(url)
    domain = parsed_url.netloc.lower()
    
    # ফেসবুক বা ইন্সটাগ্রামের ট্র্যাকিং প্যারামিটার রিমুভ করা
    if any(x in domain for x in ["facebook.com", "fb.watch", "instagram.com", "tiktok.com"]):
        url = url.split("?")[0]

    try:
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(executor, extract_media, url)
        
        if not result:
            raise HTTPException(status_code=404, detail="Media not found or restricted")
            
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)