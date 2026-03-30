import random
import yt_dlp
import logging
import time
import ipaddress
import asyncio
import hashlib
import os
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from urllib.parse import urlparse
from concurrent.futures import ThreadPoolExecutor

app = FastAPI()

# -----------------------------
# CORS
# -----------------------------
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["GET"],
    allow_headers=["*"],
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
executor = ThreadPoolExecutor(max_workers=10)

# -----------------------------
# CACHE & SETTINGS
# -----------------------------
cache = {}
CACHE_TTL = 600
rate_store = {}
RATE_LIMIT = 50
RATE_WINDOW = 60
VALID_API_KEYS = {"demo_key_123", "premium_key_456"}

# রেন্ডম ইউজার এজেন্টের লিস্ট (বিনা খরচে ব্লক এড়ানোর প্রথম ধাপ)
USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"
]

# -----------------------------
# HELPERS
# -----------------------------
def is_private_ip(host):
    try: return ipaddress.ip_address(host).is_private
    except: return False

def is_valid_url(url: str):
    try:
        parsed = urlparse(url)
        if parsed.scheme not in ["http", "https"] or not parsed.hostname: return False
        domain = parsed.hostname.replace("www.", "")
        allowed = ["youtube.com", "youtu.be", "facebook.com", "fb.watch", "fb.com", "instagram.com", "tiktok.com"]
        return any(d in domain for d in allowed)
    except: return False

# -----------------------------
# CORE ENGINE (The "Human" Simulator)
# -----------------------------
def extract_media(url: str):
    cache_key = hashlib.md5(url.encode()).hexdigest()
    if cache_key in cache:
        data, ts = cache[cache_key]
        if time.time() - ts < CACHE_TTL: return data

    # কুকি ফাইলের নাম
    fb_cookies = "facebook_cookies.txt"
    yt_cookies = "youtube_cookies.txt"
    
    ydl_opts = {
        "format": "best",
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "socket_timeout": 30,
        "retries": 10,
        "nocheckcertificate": True,
        "geo_bypass": True,
        "user_agent": random.choice(USER_AGENTS), # প্রতিবার আলাদা ডিভাইস সাজবে
        "extractor_args": {
            "youtube": {
                # ইউটিউবকে বলবে রিকোয়েস্টটি মোবাইল অ্যাপ থেকে আসছে (ব্লক হওয়ার সম্ভাবনা ০%)
                "player_client": ["android", "ios", "mweb"],
                "player_skip": ["webpage", "configs"]
            }
        }
    }

    # ডোমেইন অনুযায়ী অটো কুকিজ সিলেকশন
    if "facebook.com" in url or "fb.watch" in url or "fb.com" in url:
        if os.path.exists(fb_cookies):
            ydl_opts["cookiefile"] = fb_cookies
            logging.info("Using FB Cookies")
    elif "youtube.com" in url or "youtu.be" in url:
        if os.path.exists(yt_cookies):
            ydl_opts["cookiefile"] = yt_cookies
            logging.info("Using YT Cookies")

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)
            
            # ভিডিওর আসল ডাউনলোড লিঙ্ক বের করা
            download_url = info.get("url")
            if not download_url and "formats" in info:
                # শুধু ভিডিও আছে এমন ফরম্যাট ফিল্টার করা
                formats = [f for f in info["formats"] if f.get("url") and f.get("vcodec") != "none"]
                formats.sort(key=lambda x: (x.get("height") or 0), reverse=True)
                if formats: download_url = formats[0]["url"]

            if not download_url: return None

            result = {
                "status": "success",
                "url": download_url,
                "title": info.get("title", "Video"),
                "thumbnail": info.get("thumbnail"),
                "duration": info.get("duration"),
                "source": info.get("extractor_key")
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
    # API Key Check
    key = request.headers.get("x-api-key")
    if not key or key not in VALID_API_KEYS:
        raise HTTPException(status_code=401, detail="Invalid API Key")

    # Rate Limit Check
    now = time.time()
    user_rates = rate_store.get(key, [])
    user_rates = [t for t in user_rates if now - t < RATE_WINDOW]
    rate_store[key] = user_rates
    if len(user_rates) >= RATE_LIMIT:
        raise HTTPException(status_code=429, detail="Too many requests")
    rate_store[key].append(now)

    if not url or not is_valid_url(url):
        raise HTTPException(status_code=400, detail="Invalid or Unsupported URL")

    try:
        loop = asyncio.get_event_loop()
        # ThreadPool এ চালানো হচ্ছে যাতে সার্ভার স্লো না হয়
        result = await loop.run_in_executor(executor, extract_media, url)

        if not result:
            raise HTTPException(status_code=404, detail="Could not extract video. IP might be blocked or Video is private.")

        return result
    except HTTPException as he:
        raise he
    except Exception as e:
        logging.error(f"Server Error: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", 8000)))