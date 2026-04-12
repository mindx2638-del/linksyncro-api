import random
import yt_dlp
import logging
import time
import asyncio
import hashlib
import os
import re
from threading import Lock
from fastapi import FastAPI, HTTPException, Request, Query
from fastapi.middleware.cors import CORSMiddleware
from urllib.parse import urlparse
from concurrent.futures import ThreadPoolExecutor

# -----------------------------
# APP INITIALIZATION
# -----------------------------
app = FastAPI(
    title="LinkSyncro Media API", 
    version="5.0",
    description="Professional Media Link Extractor Pro"
)

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

# ১০ থেকে বাড়িয়ে ২০ করা হলো যেন হাই ট্রাফিক হ্যান্ডেল করতে পারে
executor = ThreadPoolExecutor(max_workers=20)

# -----------------------------
# CACHE & SETTINGS
# -----------------------------
cache = {}
cache_lock = Lock()
CACHE_TTL = 1800  # ৩০ মিনিট ক্যাশ রাখা হবে

rate_store = {}
RATE_LIMIT = 60
RATE_WINDOW = 60

# সিকিউরিটির জন্য এপিআই কি সবসময় লিস্ট বা সেট এ রাখা ভালো
VALID_API_KEYS = {"demo_key_123", "premium_key_456"}
COOKIES_DIR = "cookies"

# ইউজার এজেন্টগুলো আপডেট করা হয়েছে
USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"
]

ALLOWED_DOMAINS = (
    "youtube.com", "youtu.be",
    "facebook.com", "fb.watch", "fb.com",
    "instagram.com", "tiktok.com"
)

# -----------------------------
# HELPERS
# -----------------------------

def clean_url(url: str):
    if not url: return ""
    url = url.strip()
    # ইনভিজিবল ক্যারেক্টার এবং বাংলা দাড়ি/পাঞ্চুয়েশন রিমুভ (SAFE)
    url = re.sub(r"[\u200b\u200c\u200d\s।.,!?|—]+$", "", url)
    return url

def is_valid_url(url: str):
    try:
        parsed = urlparse(url)
        domain = (parsed.hostname or "").lower().replace("www.", "")
        return any(domain == d or domain.endswith("." + d) for d in ALLOWED_DOMAINS)
    except:
        return False

def get_ordered_cookies(site_key: str):
    if not os.path.exists(COOKIES_DIR): return [None]
    
    files = [
        f for f in os.listdir(COOKIES_DIR)
        if f.startswith(site_key) and f.endswith(".txt")
    ]
    
    if not files: return [None]

    def extract_number(name):
        try:
            nums = re.findall(r'\d+', name)
            return int(nums[-1]) if nums else 0
        except:
            return 0

    files.sort(key=extract_number)
    return [os.path.join(COOKIES_DIR, f) for f in files]

# -----------------------------
# CORE ENGINE
# -----------------------------
def extract_media(url: str):
    cache_key = hashlib.md5(url.encode()).hexdigest()

    with cache_lock:
        if cache_key in cache:
            data, ts = cache[cache_key]
            if time.time() - ts < CACHE_TTL:
                logging.info(f"Cache Hit: {url}")
                return data

    parsed_url = urlparse(url)
    domain = (parsed_url.hostname or "").lower()

    site_key, referer = "", "https://www.google.com/"

    if "instagram.com" in domain:
        site_key, referer = "instagram", "https://www.instagram.com/"
    elif any(x in domain for x in ["facebook.com", "fb.watch", "fb.com"]):
        site_key, referer = "facebook", "https://www.facebook.com/"
    elif any(x in domain for x in ["youtube.com", "youtu.be"]):
        site_key, referer = "youtube", "https://www.youtube.com/"
    elif "tiktok.com" in domain:
        site_key, referer = "tiktok", "https://www.tiktok.com/"

    cookie_list = get_ordered_cookies(site_key)

    for cookie_path in cookie_list:
        ydl_opts = {
            # ফরম্যাট লজিক শক্তিশালী করা হয়েছে (MP4 অগ্রাধিকার)
            "format": "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
            "quiet": True,
            "no_warnings": True,
            "noplaylist": True,
            "socket_timeout": 30,
            "retries": 3,
            "nocheckcertificate": True,
            "geo_bypass": True,
            "user_agent": random.choice(USER_AGENTS),
            "http_headers": {
                "Referer": referer,
                "Accept": "/",
                "Accept-Language": "en-US,en;q=0.9",
            },
            "extractor_args": {
                "youtube": {"player_client": ["android", "ios", "mweb"]},
                "facebook": {"force_video_id": True}
            }
        }

        if cookie_path:
            ydl_opts["cookiefile"] = cookie_path
            logging.info(f"Attempting with cookie: {cookie_path}")

        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)
                
                download_url = info.get("url")

                # যদি সরাসরি URL না পাওয়া যায় (যেমন Facebook/YT এর DASH streams)
                if not download_url and "formats" in info:
                    # ১. ভিডিও এবং অডিও দুটোই আছে এমন MP4 খুঁজো
                    valid_formats = [
                        f for f in info["formats"]
                        if f.get("vcodec") != "none" and f.get("acodec") != "none" and f.get("ext") == "mp4"
                    ]
                    
                    if not valid_formats:
                        valid_formats = [f for f in info["formats"] if f.get("url")]

                    if valid_formats:
                        # রেজোলিউশন অনুযায়ী সাজানো
                        valid_formats.sort(key=lambda x: (x.get("height") or 0), reverse=True)
                        download_url = valid_formats[0]["url"]

                if download_url:
                    result = {
                        "status": "success",
                        "url": download_url,
                        "title": info.get("title", "Media Content"),
                        "thumbnail": info.get("thumbnail"),
                        "duration": info.get("duration"),
                        "source": info.get("extractor_key", domain),
                        "timestamp": int(time.time())
                    }

                    with cache_lock:
                        cache[cache_key] = (result, time.time())
                        if len(cache) > 1000: cache.clear()
                    
                    return result

        except Exception as e:
            logging.error(f"YT-DLP ERROR ({site_key}): {str(e)}")
            continue # পরবর্তী কুকি দিয়ে চেষ্টা করবে

    return None

# -----------------------------
# ROUTES
# -----------------------------
@app.get("/get_media")
async def get_media(
    request: Request,
    url: str = Query(..., description="The media URL to extract")
):
    # API KEY VALIDATION
    api_key = request.headers.get("x-api-key")
    if not api_key or api_key not in VALID_API_KEYS:
        raise HTTPException(status_code=401, detail="Unauthorized: Access Denied")

    # RATE LIMITING
    now = time.time()
    user_rates = rate_store.get(api_key, [])
    user_rates = [t for t in user_rates if now - t < RATE_WINDOW]
    
    if len(user_rates) >= RATE_LIMIT:
        raise HTTPException(status_code=429, detail="Too many requests. Slow down!")
    
    user_rates.append(now)
    rate_store[api_key] = user_rates

    # URL PROCESSING
    url = clean_url(url)
    if not url:
        raise HTTPException(status_code=400, detail="Invalid request: URL is empty")

    # FB/IG এর ভিডিও আইডি বা প্যারামিটার ঠিক রাখতে কাস্টম ক্লিনিং
    if "?" in url:
        if "instagram.com" in url:
            url = url.split("?")[0]  # Instagram এর জন্য ক্লিনিং নিরাপদ
        elif "facebook.com" in url or "fb.watch" in url:
            # Facebook এর জন্য split করা যাবে না, কারণ ID '?' এর পরে থাকতে পারে
            pass

    if not is_valid_url(url):
        raise HTTPException(status_code=400, detail="Domain not supported or invalid URL")

    try:
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(executor, extract_media, url)

        if not result:
            raise HTTPException(
                status_code=404,
                detail="Failed to extract media. Private video or restricted content."
            )

        return result

    except HTTPException as he:
        raise he
    except Exception as e:
        logging.error(f"Critical Server Error: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")

# -----------------------------
# RUN
# -----------------------------
if __name__ == "__main__":
    import uvicorn
    # Render/Heroku এর জন্য পোর্ট ডাইনামিক রাখা হয়েছে
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)