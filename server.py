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
app = FastAPI(title="LinkSyncro Pro API", version="4.0")

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

# আধুনিক ব্রাউজার এজেন্ট যা ইউটিউব/টিকটক সহজে ব্লক করে না
USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36"
]

# -----------------------------
# CORE ENGINE (The Magic Starts Here)
# -----------------------------
def extract_media(url: str):
    cache_key = hashlib.md5(url.encode()).hexdigest()
    if cache_key in cache:
        data, ts = cache[cache_key]
        if time.time() - ts < CACHE_TTL:
            return data

    # yt-dlp কনফিগারেশন - যা YouTube & TikTok সাপোর্ট করবে
    ydl_opts = {
        # সেরা কোয়ালিটি MP4 সিলেক্ট করা
        "format": "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "geo_bypass": True,
        "nocheckcertificate": True,
        "socket_timeout": 30,
        "retries": 10,
        "user_agent": random.choice(USER_AGENTS),
        # ইউটিউব এর "Sign in to confirm you are not a bot" এড়াতে
        "extractor_args": {
            "youtube": {
                "player_client": ["android", "ios", "mweb"],
                "player_skip": ["webpage", "configs"]
            }
        },
        "http_headers": {
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
            "Referer": "https://www.google.com/",
        }
    }

    # গুরুত্বপূর্ণ: cookies.txt ফাইল থাকলে সেটি ব্যবহার করবে
    # Render-এ তোমার প্রজেক্টের রুট ফোল্ডারে cookies.txt ফাইলটি আপলোড করে দাও
    if os.path.exists("cookies.txt"):
        ydl_opts["cookiefile"] = "cookies.txt"
        logging.info("Using cookies.txt for authentication")

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            # সরাসরি তথ্য বের করা
            info = ydl.extract_info(url, download=False)
            
            # ভিডিও ইউআরএল খোঁজার উন্নত লজিক
            download_url = None
            
            # ১. সরাসরি ইউআরএল চেক
            if "url" in info:
                download_url = info["url"]
            
            # ২. ফরম্যাট লিস্ট থেকে সেরাটি খুঁজে বের করা
            if not download_url and "formats" in info:
                # অডিও এবং ভিডিও দুটোই আছে এমন ফরম্যাট খোঁজা
                formats = [f for f in info["formats"] if f.get("vcodec") != "none" and f.get("acodec") != "none"]
                if not formats:
                    formats = [f for f in info["formats"] if f.get("url")]
                
                if formats:
                    # রেজোলিউশন অনুযায়ী সর্ট করা
                    formats.sort(key=lambda x: (x.get("height") or 0), reverse=True)
                    download_url = formats[0]["url"]

            if not download_url:
                return None

            result = {
                "status": "success",
                "url": download_url,
                "title": info.get("title", "Video"),
                "thumbnail": info.get("thumbnail"),
                "duration": info.get("duration"),
                "source": info.get("extractor_key", "Unknown")
            }

            cache[cache_key] = (result, time.time())
            return result

    except Exception as e:
        logging.error(f"Error extracting {url}: {str(e)}")
        return None

# -----------------------------
# ROUTES
# -----------------------------
@app.get("/get_media")
async def get_media(url: str, request: Request):
    # API Key Validation
    api_key = request.headers.get("x-api-key")
    if not api_key or api_key not in VALID_API_KEYS:
        raise HTTPException(status_code=401, detail="Invalid API Key")

    if not url:
        raise HTTPException(status_code=400, detail="URL is required")

    # URL ক্লিনিং
    if "facebook.com" in url or "instagram.com" in url or "tiktok.com" in url:
        url = url.split("?")[0]

    try:
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(executor, extract_media, url)
        
        if not result:
            raise HTTPException(status_code=404, detail="Could not extract media. Private or restricted content.")
            
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)