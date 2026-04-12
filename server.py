import random
import yt_dlp
import logging
import time
import asyncio
import hashlib
import os
from typing import Optional
from fastapi import FastAPI, HTTPException, Request, Depends, Query
from fastapi.middleware.cors import CORSMiddleware
from urllib.parse import urlparse
from concurrent.futures import ThreadPoolExecutor
from pydantic import BaseModel, HttpUrl

# -----------------------------
# CONFIGURATION & LOGGING
# -----------------------------
logging.basicConfig(
    level=logging.INFO, 
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("LinkSyncro")

app = FastAPI(
    title="LinkSyncro Media API", 
    version="3.0",
    description="Advanced Social Media Video Downloader API"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ইউজারের লোড হ্যান্ডেল করার জন্য থ্রেড পুল
executor = ThreadPoolExecutor(max_workers=30)

# -----------------------------
# DATA MODELS (Schemas)
# -----------------------------
class MediaResponse(BaseModel):
    status: str
    url: str
    title: str
    thumbnail: Optional[str] = None
    duration: Optional[int] = None
    source: str
    timestamp: float

# -----------------------------
# CONSTANTS & IN-MEMORY STORE
# -----------------------------
CACHE = {}
CACHE_TTL = 3600  # ১ ঘণ্টা ক্যাশ
RATE_LIMIT_STORE = {}
RATE_LIMIT_COUNT = 50
RATE_WINDOW = 60

# সিকিউরিটি: এনভায়রনমেন্ট ভেরিয়েবল থেকে কী নেওয়া ভালো
VALID_API_KEYS = os.getenv("API_KEYS", "demo_key_123,premium_key_456").split(",")

USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/123.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/122.0.0.0 Safari/537.36",
    "Mozilla/5.0 (X11; Linux x86_64) Chrome/121.0.0.0 Safari/537.36"
]

# -----------------------------
# CORE LOGIC (Utility Functions)
# -----------------------------

def get_cache_key(url: str) -> str:
    return hashlib.md5(url.encode()).hexdigest()

def clean_url(url: str) -> str:
    """সোশ্যাল মিডিয়া ট্র্যাকিং প্যারামিটার রিমুভ করে"""
    parsed = urlparse(url)
    if any(domain in parsed.netloc for domain in ["facebook.com", "instagram.com", "tiktok.com"]):
        return f"{parsed.scheme}://{parsed.netloc}{parsed.path}"
    return url

def is_supported(url: str) -> bool:
    allowed = ["youtube.com", "youtu.be", "facebook.com", "fb.watch", "instagram.com", "tiktok.com", "twitter.com", "x.com"]
    return any(d in url for d in allowed)

# -----------------------------
# EXTRACTION ENGINE
# -----------------------------

def extract_media_logic(url: str) -> dict:
    # ১. ক্যাশ চেক
    key = get_cache_key(url)
    if key in CACHE:
        data, expiry = CACHE[key]
        if time.time() < expiry:
            logger.info(f"Cache Hit for: {url}")
            return data

    # ২. কুকি ফাইল চেক
    cookie_files = {
        "facebook.com": "facebook_cookies.txt",
        "instagram.com": "instagram_cookies.txt",
        "youtube.com": "youtube_cookies.txt"
    }
    
    selected_cookie = next((v for k, v in cookie_files.items() if k in url), None)

    ydl_opts = {
        "format": "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "socket_timeout": 30,
        "retries": 3,
        "geo_bypass": True,
        "user_agent": random.choice(USER_AGENTS),
    }

    if selected_cookie and os.path.exists(selected_cookie):
        ydl_opts["cookiefile"] = selected_cookie
        logger.info(f"Using cookies for {url}")

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)
            
            # ভিডিও ইউআরএল খোঁজার উন্নত লজিক
            formats = info.get('formats', [])
            # ফিল্টার: যেখানে অডিও এবং ভিডিও দুটোই আছে এবং mp4
            video_url = info.get('url')
            
            if not video_url and formats:
                best_format = next((f for f in reversed(formats) 
                                   if f.get('vcodec') != 'none' and f.get('acodec') != 'none' and f.get('ext') == 'mp4'), 
                                  formats[-1])
                video_url = best_format.get('url')

            if not video_url:
                return None

            result = {
                "status": "success",
                "url": video_url,
                "title": info.get("title", "No Title"),
                "thumbnail": info.get("thumbnail"),
                "duration": info.get("duration"),
                "source": info.get("extractor_key", "unknown"),
                "timestamp": time.time()
            }
            
            # ক্যাশ সেভ করা
            CACHE[key] = (result, time.time() + CACHE_TTL)
            return result

    except Exception as e:
        logger.error(f"Extraction failed: {str(e)}")
        return None

# -----------------------------
# API ROUTES
# -----------------------------

@app.get("/api/v3/fetch", response_model=MediaResponse)
async def fetch_media(
    request: Request,
    url: str = Query(..., description="The video URL to process"),
    api_key: str = Query(..., alias="key")
):
    # ১. API Key ভ্যালিডেশন
    if api_key not in VALID_API_KEYS:
        raise HTTPException(status_code=401, detail="Invalid API Key")

    # ২. রেট লিমিটিং (API Key ভিত্তিক)
    now = time.time()
    user_requests = RATE_LIMIT_STORE.get(api_key, [])
    user_requests = [t for t in user_requests if now - t < RATE_WINDOW]
    RATE_LIMIT_STORE[api_key] = user_requests
    
    if len(user_requests) >= RATE_LIMIT_COUNT:
        raise HTTPException(status_code=429, detail="Rate limit exceeded. Try again in a minute.")
    
    RATE_LIMIT_STORE[api_key].append(now)

    # ৩. URL ক্লিন এবং ভ্যালিডেশন
    target_url = clean_url(url)
    if not is_supported(target_url):
        raise HTTPException(status_code=400, detail="Domain not supported or invalid URL")

    # ৪. এক্সিকিউশন
    try:
        loop = asyncio.get_running_loop()
        result = await loop.run_in_executor(executor, extract_media_logic, target_url)
        
        if not result:
            raise HTTPException(status_code=404, detail="Media not found or protected content.")
            
        return result

    except HTTPException as e:
        raise e
    except Exception as e:
        logger.critical(f"System Error: {str(e)}")
        raise HTTPException(status_code=500, detail="An internal error occurred.")

# -----------------------------
# RUNNER
# -----------------------------
if __name__ == "__main__":
    import uvicorn
    # Render/Heroku এর জন্য ডাইনামিক পোর্ট
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)