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
executor = ThreadPoolExecutor(max_workers=25) # ১০ থেকে বাড়িয়ে ২৫ করা হলো

# -----------------------------
# CACHE & SETTINGS
# -----------------------------
cache = {}
CACHE_TTL = 1200 
rate_store = {}
RATE_LIMIT = 60
RATE_WINDOW = 60
VALID_API_KEYS = {"demo_key_123", "premium_key_456"}
COOKIES_DIR = "cookies" # কুকি ফোল্ডারের নাম

USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
]

# -----------------------------
# HELPERS
# -----------------------------
def is_valid_url(url: str):
    try:
        parsed = urlparse(url)
        domain = parsed.hostname.replace("www.", "")
        allowed = ["youtube.com", "youtu.be", "facebook.com", "fb.watch", "fb.com", "instagram.com", "tiktok.com"]
        return any(d in domain for d in allowed)
    except:
        return False

# -----------------------------
# CORE ENGINE
# -----------------------------
def extract_media(url: str):
    # ১. ক্যাশ চেক
    cache_key = hashlib.md5(url.encode()).hexdigest()
    if cache_key in cache:
        data, ts = cache[cache_key]
        if time.time() - ts < CACHE_TTL:
            logging.info(f"Cache Hit: {url}")
            return data

    # ২. ডোমেইন ডিটেকশন
    parsed_url = urlparse(url)
    domain = parsed_url.hostname or ""
    current_ua = random.choice(USER_AGENTS)

    # ৩. বেসিক yt-dlp কনফিগারেশন
    ydl_opts = {
        "format": "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "socket_timeout": 45, 
        "retries": 5,
        "nocheckcertificate": True,
        "geo_bypass": True,
        "user_agent": current_ua,
        "http_headers": {
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
        },
    }

    # ৪. ডোমেইন অনুযায়ী অটোমেটিক কুকি ও হেডার সিলেকশন (ডাইনামিক লজিক)
    site_config = {
        "instagram.com": {"file": "instagram.txt", "referer": "https://www.instagram.com/"},
        "facebook.com": {"file": "facebook.txt", "referer": "https://www.facebook.com/"},
        "fb.watch": {"file": "facebook.txt", "referer": "https://www.facebook.com/"},
        "fb.com": {"file": "facebook.txt", "referer": "https://www.facebook.com/"},
        "youtube.com": {"file": "youtube.txt", "referer": "https://www.youtube.com/"},
        "youtu.be": {"file": "youtube.txt", "referer": "https://www.youtube.com/"},
    }

    # সঠিক কুকি ফাইল সেট করা
    for site, config in site_config.items():
        if site in domain:
            cookie_path = os.path.join(COOKIES_DIR, config["file"])
            if os.path.exists(cookie_path):
                ydl_opts["cookiefile"] = cookie_path
                logging.info(f"Using cookies: {config['file']}")
            
            # স্পেশাল হেডার (ইনস্টাগ্রাম ও ফেসবুকের ব্লকিং এড়াতে)
            ydl_opts["http_headers"]["Referer"] = config["referer"]
            if "instagram" in site:
                ydl_opts["http_headers"].update({
                    "Sec-Fetch-Mode": "navigate",
                    "Sec-Fetch-Site": "same-origin",
                    "Origin": "https://www.instagram.com"
                })
            break

    # ৫. এক্সট্রাকশন লজিক
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)
            download_url = info.get("url")
            
            if not download_url and "formats" in info:
                valid_formats = [f for f in info["formats"] if f.get("vcodec") != "none" and f.get("acodec") != "none"]
                if not valid_formats:
                    valid_formats = [f for f in info["formats"] if f.get("url")]
                
                if valid_formats:
                    valid_formats.sort(key=lambda x: (x.get("height") or 0), reverse=True)
                    download_url = valid_formats[0]["url"]

            if not download_url: return None

            result = {
                "status": "success",
                "url": download_url,
                "title": info.get("title", "Video"),
                "thumbnail": info.get("thumbnail"),
                "duration": info.get("duration"),
                "source": info.get("extractor_key", domain)
            }
            
            cache[cache_key] = (result, time.time())
            if len(cache) > 1000: cache.pop(next(iter(cache)))
            return result
    except Exception as e:
        logging.error(f"yt-dlp error: {str(e)}")
        return None

# -----------------------------
# ROUTES
# -----------------------------
@app.get("/get_media")
async def get_media(url: str, request: Request):
    key = request.headers.get("x-api-key")
    if not key or key not in VALID_API_KEYS:
        raise HTTPException(status_code=401, detail="Unauthorized")

    now = time.time()
    user_rates = rate_store.get(key, [])
    user_rates = [t for t in user_rates if now - t < RATE_WINDOW]
    rate_store[key] = user_rates
    if len(user_rates) >= RATE_LIMIT:
        raise HTTPException(status_code=429, detail="Rate limit exceeded")
    rate_store[key].append(now)

    if not url: raise HTTPException(status_code=400, detail="URL is required")
        
    if "?" in url and ("facebook" in url or "instagram" in url):
        url = url.split("?")[0]

    if not is_valid_url(url):
        raise HTTPException(status_code=400, detail="Invalid URL")

    try:
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(executor, extract_media, url)
        if not result:
            raise HTTPException(status_code=404, detail="Content restricted or IP blocked")
        return result
    except Exception:
        raise HTTPException(status_code=500, detail="Server error")

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)