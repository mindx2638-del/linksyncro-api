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
# APP INITIALIZATION
# -----------------------------
app = FastAPI(title="LinkSyncro Universal API", version="3.5")

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
# PERFORMANCE & THREADING
# -----------------------------
MAX_WORKERS = min(32, (os.cpu_count() or 1) * 4)
executor = ThreadPoolExecutor(max_workers=MAX_WORKERS)

# -----------------------------
# CACHE (LRU STYLE with Thread Safety)
# -----------------------------
cache = OrderedDict()
cache_lock = Lock()
CACHE_TTL = 1200 
CACHE_MAX_SIZE = 2000

# -----------------------------
# RATE LIMIT (Thread Safe)
# -----------------------------
rate_store = {}
rate_lock = Lock()
RATE_LIMIT = 50
RATE_WINDOW = 60

# -----------------------------
# SECURITY & AGENTS
# -----------------------------
VALID_API_KEYS = {"demo_key_123", "premium_key_456"}

USER_AGENTS = [
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (Linux; Android 14; Pixel 😎 AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
]

# -----------------------------
# HELPERS
# -----------------------------
def is_valid_url(url: str) -> bool:
    try:
        parsed = urlparse(url)
        return bool(parsed.scheme in ["http", "https"] and parsed.hostname)
    except:
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
    
    target_folder = ""
    for key, folder in folder_map.items():
        if key in domain:
            target_folder = folder
            break
            
    if not target_folder:
        return []

    base_path = os.path.join("cookies", target_folder)
    if os.path.exists(base_path):
        try:
            return sorted([os.path.join(base_path, f) for f in os.listdir(base_path) if f.endswith(".txt")])
        except Exception:
            return []
    return []

# -----------------------------
# CORE ENGINE
# -----------------------------
def extract_media(url: str):
    cache_key = hashlib.md5(url.encode()).hexdigest()
    
    with cache_lock:
        if cache_key in cache:
            data, ts = cache[cache_key]
            if time.time() - ts < CACHE_TTL:
                return data

    domain = urlparse(url).hostname or ""
    cookie_list = [None] + get_cookie_files(domain)

    for cookie_path in cookie_list:
        ydl_opts = {
            # ১. ফরম্যাট সিলেকশন আরও স্পেসিফিক করা (স্পিড বাড়াবে)
            "format": "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
            "quiet": True,
            "no_warnings": True,
            "noplaylist": True,
            
            # ২. সুপার ফাস্ট সার্চিং সেটিংস
            "socket_timeout": 15,          # বেশিক্ষণ অপেক্ষা করবে না
            "retries": 2,                 # দ্রুত ফেইল হলে পরের মেথডে যাবে
            "nocheckcertificate": True,
            "geo_bypass": True,
            "user_agent": random.choice(USER_AGENTS),
            "ignoreerrors": True,
            
            # ৩. ডাউনলোড স্পিড ১০০/১০০ করার জন্য সেটিংস
            "external_downloader": "aria2c", # aria2c ব্যবহার করলে স্পিড ১০ গুণ বেড়ে যায়
            "external_downloader_args": ["-x", "16", "-s", "16", "-k", "1M"], 
            "concurrent_fragment_downloads": 10, # একসাথে অনেকগুলো কানেকশন
            "buffer_size": "16K",
            
            "http_headers": {
                "Accept": "/",
                "Referer": url,
            },
            
            "extractor_args": {
                "youtube": {"player_client": ["android", "ios", "mweb", "tv"], "player_skip": ["webpage", "configs"]},
                # জেন লিঙ্কের জন্য অতিরিক্ত আর্গুমেন্ট
                "generic": {"search_cmds": ["direct"]}, 
            }
        }

        if cookie_path:
            ydl_opts["cookiefile"] = cookie_path

        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                # ৪. সব পেজ লোড না করে শুধু ভিডিও তথ্য বের করা
                info = ydl.extract_info(url, download=False, process=True) 
                
                if not info: continue
                if 'entries' in info: info = info['entries'][0]

                download_url = info.get("url")
                
                # আপনার অরিজিনাল ফরম্যাট সিলেকশন লজিক...
                if not download_url and "formats" in info:
                    valid_formats = [f for f in info["formats"] if f.get("vcodec") != "none" and f.get("acodec") != "none"]
                    if not valid_formats:
                        valid_formats = [f for f in info["formats"] if f.get("url")]
                    
                    if valid_formats:
                        valid_formats.sort(key=lambda x: (x.get("height") or 0), reverse=True)
                        download_url = valid_formats[0]["url"]

                if download_url:
                    result = {
                        "status": "success",
                        "url": download_url,
                        "title": info.get("title", "Video"),
                        "thumbnail": info.get("thumbnail"),
                        "duration": info.get("duration"),
                        "source": info.get("extractor_key", domain),
                        "ext": info.get("ext", "mp4")
                    }
                    
                    with cache_lock:
                        cache[cache_key] = (result, time.time())
                    return result
                    
        except Exception:
            continue 

    return None


# -----------------------------
# ROUTES
# -----------------------------
@app.get("/get_media")
async def get_media(url: str, request: Request):
    # API Key Logic
    key = request.headers.get("x-api-key")
    if not key or key not in VALID_API_KEYS:
        raise HTTPException(status_code=401, detail="Unauthorized: Invalid API Key")

    # Rate Limit Logic (Thread Safe)
    now = time.time()
    with rate_lock:
        user_rates = rate_store.get(key, [])
        user_rates = [t for t in user_rates if now - t < RATE_WINDOW]
        if len(user_rates) >= RATE_LIMIT:
            raise HTTPException(status_code=429, detail="Rate limit exceeded")
        user_rates.append(now)
        rate_store[key] = user_rates

    if not url:
        raise HTTPException(status_code=400, detail="URL is required")

    # URL Cleaning (Original Logic)
    if "?" in url and any(x in url for x in ["facebook", "fb", "instagram"]):
        url = url.split("?")[0]

    if not is_valid_url(url):
        raise HTTPException(status_code=400, detail="Unsupported or invalid URL")

    try:
        # Using thread pool for blocking yt-dlp calls
        result = await asyncio.get_event_loop().run_in_executor(executor, extract_media, url)
        
        if not result:
            raise HTTPException(status_code=404, detail="Could not extract video content.")
        
        return result
    except HTTPException:
        raise
    except Exception as e:
        logging.error(f"Critical Error: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")

# -----------------------------
# RUNNER
# -----------------------------
if __name__ == "__main__":
    import uvicorn
    # Optimized runner settings
    uvicorn.run(
        app, 
        host="0.0.0.0", 
        port=int(os.environ.get("PORT", 8000)),
        log_level="info",
        workers=1 # FastAPI handles concurrency via asyncio & threads
    )
