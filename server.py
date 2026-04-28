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

import json
import redis.asyncio as redis
from contextlib import asynccontextmanager

# Redis কানেকশন সেটআপ
redis_client = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global redis_client
    redis_client = redis.Redis(host='localhost', port=6379, db=0, decode_responses=True)
    yield
    await redis_client.close()

# এখন app ইনিশিয়ালাইজ করার সময় lifespan যোগ করুন:
app = FastAPI(title="LinkSyncro Universal API", version="3.0", lifespan=lifespan)

# -----------------------------
# APP INITIALIZATION
# -----------------------------
app = FastAPI(title="LinkSyncro Universal API", version="3.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["GET"],
    allow_headers=["*"],
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
executor = ThreadPoolExecutor(max_workers=50) # থ্রেড পুল কিছুটা বাড়ানো হয়েছে পারফরম্যান্সের জন্য

# -----------------------------
# CACHE & SETTINGS
# -----------------------------
CACHE_TTL = 1200 
RATE_LIMIT = 50
RATE_WINDOW = 60
VALID_API_KEYS = {"demo_key_123", "premium_key_456"}

# Android এবং iOS সাপোর্ট নিশ্চিত করতে আধুনিক মোবাইল ইউজার এজেন্ট
USER_AGENTS = [
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (Linux; Android 14; Pixel 8 AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
]

# -----------------------------
# HELPERS
# -----------------------------
def is_valid_url(url: str):
    """আপনার অরিজিনাল লজিক ঠিক রেখে বিশ্বের সব লিঙ্ক সাপোর্টের জন্য আপডেট"""
    try:
        parsed = urlparse(url)
        if parsed.scheme not in ["http", "https"] or not parsed.hostname:
            return False
        
        # 'allowed' লিস্টের বাধ্যবাধকতা সরিয়ে দেওয়া হয়েছে যাতে সব সাইট কাজ করে
        # তবে আপনার আগের চেনা সাইটগুলোও এর অন্তর্ভুক্ত থাকবে
        return True 
    except:
        return False

def get_cookie_files(domain):
    """আপনার দেওয়া ডোমেইন ভিত্তিক কুকি লজিক (অপরিবর্তিত)"""
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
        files = [os.path.join(base_path, f) for f in os.listdir(base_path) if f.endswith(".txt")]
        files.sort()
        return files
    return []

# -----------------------------
# CORE ENGINE
# -----------------------------
def extract_media(url: str):
    domain = urlparse(url).hostname or ""
    
    # কুকি লিস্ট তৈরি
    cookie_list = [None]
    cookie_list.extend(get_cookie_files(domain))

    for cookie_path in cookie_list:
        ydl_opts = {
            "format": "best[height<=1440]/best", 
            "quiet": True,
            "no_warnings": True,
            "noplaylist": True,
            "socket_timeout": 60,
            "retries": 10,
            "nocheckcertificate": True,
            "geo_bypass": True,
            "user_agent": random.choice(USER_AGENTS),
            "extractor_args": {
                "youtube": {"player_client": ["android", "ios", "mweb", "tv"], "player_skip": ["webpage", "configs"]},
                "instagram": {"force_subtitles": False},
                "facebook": {"force_generic_extractor": False}
            }
        }

        if cookie_path:
            ydl_opts["cookiefile"] = cookie_path
            logging.info(f"Attempting with Cookie: {cookie_path}")
        else:
            logging.info(f"Attempting WITHOUT cookies for: {url}")

        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)
                
                download_url = info.get("url")
                
                # ফরম্যাট সিলেকশন লজিক
                if not download_url and "formats" in info:
                    valid_formats = [f for f in info["formats"] if f.get("vcodec") != "none" and f.get("acodec") != "none"]
                    if not valid_formats:
                        valid_formats = [f for f in info["formats"] if f.get("url")]
                    
                    if valid_formats:
                        valid_formats.sort(key=lambda x: (x.get("height") or 0), reverse=True)
                        download_url = valid_formats[0]["url"]

                if download_url:
                    # রেজাল্ট তৈরি করা হচ্ছে (এটাই আপনার রাউটে রিটার্ন হিসেবে যাবে)
                    return {
                        "status": "success",
                        "url": download_url,
                        "title": info.get("title", "Video"),
                        "thumbnail": info.get("thumbnail"),
                        "duration": info.get("duration"),
                        "source": info.get("extractor_key", domain)
                    }
                    
        except Exception as e:
            if not cookie_path:
                logging.warning(f"Failed without cookies. Error: {str(e)}")
            else:
                logging.error(f"Failed with cookie {cookie_path}: {str(e)}")
            continue 

    return None
# -----------------------------
# ROUTES
# -----------------------------
@app.get("/get_media")
async def get_media(url: str, request: Request):
    # API Key চেক
    key = request.headers.get("x-api-key")
    if not key or key not in VALID_API_KEYS:
        raise HTTPException(status_code=401, detail="Unauthorized")

    # Redis Rate Limiting
    rate_key = f"rate:{key}"
    count = await redis_client.incr(rate_key)
    if count == 1: await redis_client.expire(rate_key, RATE_WINDOW)
    if count > RATE_LIMIT:
        raise HTTPException(status_code=429, detail="Rate limit exceeded")

    if not url: raise HTTPException(status_code=400, detail="URL is required")
    if "?" in url and any(x in url for x in ["facebook", "fb", "instagram"]): url = url.split("?")[0]
    if not is_valid_url(url): raise HTTPException(status_code=400, detail="Invalid URL")

    # Redis Cache Check
    cache_key = f"cache:{hashlib.md5(url.encode()).hexdigest()}"
    cached_data = await redis_client.get(cache_key)
    if cached_data:
        return json.loads(cached_data)

    # Extraction
    loop = asyncio.get_event_loop()
    result = await loop.run_in_executor(executor, extract_media, url)
    
    if not result:
        raise HTTPException(status_code=404, detail="Could not extract video.")

    # Redis-এ সেভ করা
    await redis_client.set(cache_key, json.dumps(result), ex=CACHE_TTL)
    return result

# -----------------------------
# RUNNER
# -----------------------------
if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)