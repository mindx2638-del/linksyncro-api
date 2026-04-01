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
app = FastAPI(title="LinkSyncro Universal API", version="3.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["GET"],
    allow_headers=["*"],
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
# হাই-ট্রাফিক হ্যান্ডেল করার জন্য ২০ জন ওয়ার্কার
executor = ThreadPoolExecutor(max_workers=20)

# -----------------------------
# CACHE & SETTINGS
# -----------------------------
cache = {}
CACHE_TTL = 1200 
rate_store = {}
RATE_LIMIT = 50
RATE_WINDOW = 60
# এই কি-গুলো তোমার ফ্লাটার অ্যাপের হেডার (x-api-key) এ ব্যবহার করবে
VALID_API_KEYS = {"demo_key_123", "premium_key_456"}

USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36"
]

# -----------------------------
# HELPERS (Universal Logic)
# -----------------------------
def is_valid_url(url: str):
    try:
        parsed = urlparse(url)
        # নির্দিষ্ট সাইট বাদ দিয়ে এখন যেকোনো HTTP/HTTPS লিঙ্ক এলাউড
        return parsed.scheme in ["http", "https"] and bool(parsed.hostname)
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

    # ২. জেনেরিক সেটিংস (১০০০+ সাইট সাপোর্ট করার জন্য)
    ydl_opts = {
        # MP4 কোয়ালিটি প্রায়োরিটি পাবে
        "format": "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "socket_timeout": 45,
        "retries": 5,
        "nocheckcertificate": True,
        "geo_bypass": True,
        "user_agent": random.choice(USER_AGENTS),
        "http_headers": {
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
        },
    }

    # ৩. কুকি ফাইল চেক (যদি থাকে)
    # তোমার Render প্রজেক্টে cookies.txt নামে ফাইল রাখলে এটি অটো পাবে
    if os.path.exists("cookies.txt"):
        ydl_opts["cookiefile"] = "cookies.txt"

    # ৪. এক্সট্রাকশন লজিক
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)
            
            # ডাউনলোড ইউআরএল বের করা
            download_url = info.get("url")
            
            # যদি সরাসরি ইউআরএল না পাওয়া যায় (যেমন ইউটিউব বা ইনস্টাগ্রাম)
            if not download_url and "formats" in info:
                # অডিও এবং ভিডিও দুটোই আছে এমন কম্বাইন্ড ফরমেট খোঁজা
                valid_formats = [f for f in info["formats"] if f.get("vcodec") != "none" and f.get("acodec") != "none"]
                
                if not valid_formats:
                    # ব্যাকআপ: যেকোনো ফরমেট যাতে ইউআরএল আছে
                    valid_formats = [f for f in info["formats"] if f.get("url")]
                
                if valid_formats:
                    # রেজোলিউশন অনুযায়ী সবচেয়ে ভালোটি নেওয়া
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
                "source": info.get("extractor_key", "Universal")
            }

            # ক্যাশে সেভ করা
            cache[cache_key] = (result, time.time())
            
            # মেমোরি ম্যানেজমেন্ট
            if len(cache) > 1000:
                cache.pop(next(iter(cache)))
                
            return result
    except Exception as e:
        logging.error(f"yt-dlp error: {str(e)}")
        return None

# -----------------------------
# ROUTES
# -----------------------------
@app.get("/get_media")
async def get_media(url: str, request: Request):
    # ১. API Key Check (সিকিউরিটির জন্য)
    key = request.headers.get("x-api-key")
    if not key or key not in VALID_API_KEYS:
        raise HTTPException(status_code=401, detail="Unauthorized: Invalid API Key")

    # ২. Rate Limit Check
    now = time.time()
    user_rates = rate_store.get(key, [])
    user_rates = [t for t in user_rates if now - t < RATE_WINDOW]
    rate_store[key] = user_rates
    if len(user_rates) >= RATE_LIMIT:
        raise HTTPException(status_code=429, detail="Rate limit exceeded. Slow down!")
    rate_store[key].append(now)

    # ৩. URL ভ্যালিডেশন
    if not url:
        raise HTTPException(status_code=400, detail="URL is required")
        
    # ফেসবুক/ইনস্টাগ্রাম প্যারামিটার ক্লিনআপ (যাতে ক্যাশ ভালো কাজ করে)
    if "?" in url:
        domain = urlparse(url).hostname or ""
        if any(d in domain for d in ["facebook.com", "fb.watch", "instagram.com"]):
            url = url.split("?")[0]

    if not is_valid_url(url):
        raise HTTPException(status_code=400, detail="Invalid or unsupported URL")

    # ৪. এক্সিকিউশন
    try:
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(executor, extract_media, url)
        
        if not result:
            raise HTTPException(status_code=404, detail="Could not extract video. It might be private or restricted.")
            
        return result
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