import random
import yt_dlp
import logging
import time
import asyncio
import hashlib
import os
import re
import firebase_admin
from firebase_admin import credentials, firestore
from threading import Lock
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from urllib.parse import urlparse
from concurrent.futures import ThreadPoolExecutor

# -----------------------------
# FIREBASE & APP INITIALIZATION
# -----------------------------
# নিশ্চিত করুন serviceAccountKey.json ফাইলটি আপনার কোডের পাশেই আছে
if not firebase_admin._apps:
    cred = credentials.Certificate("serviceAccountKey.json")
    firebase_admin.initialize_app(cred)

db = firestore.client()
app = FastAPI(title="LinkSyncro Media API", version="5.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["GET"],
    allow_headers=["*"],
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
executor = ThreadPoolExecutor(max_workers=15)

# -----------------------------
# CACHE & SETTINGS
# -----------------------------
cache = {}
cache_lock = Lock()
CACHE_TTL = 1200
rate_store = {}
RATE_LIMIT = 60
RATE_WINDOW = 60
VALID_API_KEYS = {"demo_key_123", "premium_key_456"}

USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
]

ALLOWED_DOMAINS = ("youtube.com", "youtu.be", "facebook.com", "fb.watch", "fb.com", "instagram.com", "tiktok.com")

# -----------------------------
# HELPERS
# -----------------------------

def clean_url(url: str):
    if not url: return ""
    url = url.strip()
    url = re.sub(r"[।.,!?|—\s\u200b\u200c\u200d]+$", "", url)
    return url

def is_valid_url(url: str):
    try:
        parsed = urlparse(url)
        domain = (parsed.hostname or "").replace("www.", "")
        return any(domain == d or domain.endswith("." + d) for d in ALLOWED_DOMAINS)
    except: return False

def get_cookies_from_firebase(site_key: str):
    """Firebase থেকে কুকি ডাটা নিয়ে সাময়িক ফাইল তৈরি করে"""
    try:
        docs = db.collection('accounts').where('status', '==', 'active').limit(1).get()
        for doc in docs:
            data = doc.to_dict()
            if data.get('cookie_text'):
                cookie_filename = f"temp_cookies_{site_key}.txt"
                with open(cookie_filename, "w", encoding="utf-8") as f:
                    f.write(data['cookie_text'])
                return cookie_filename
    except Exception as e:
        logging.error(f"Firebase Sync Error: {str(e)}")
    return None

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
    domain = parsed_url.hostname or ""
    site_key, referer = "", ""

    if "instagram.com" in domain:
        site_key, referer = "instagram", "https://www.instagram.com/"
    elif any(x in domain for x in ["facebook.com", "fb.watch", "fb.com"]):
        site_key, referer = "facebook", "https://www.facebook.com/"
    elif any(x in domain for x in ["youtube.com", "youtu.be"]):
        site_key, referer = "youtube", "https://www.youtube.com/"
    elif "tiktok.com" in domain:
        site_key, referer = "tiktok", "https://www.tiktok.com/"

    # Firebase থেকে অটোমেটিক কুকি ফাইল নেওয়া
    cookie_path = get_cookies_from_firebase(site_key) if site_key in ["facebook", "instagram"] else None

    ydl_opts = {
        "format": "bestvideo+bestaudio/best", # অডিও-ভিডিও কম্বাইন করার সেরা লজিক
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "socket_timeout": 30,
        "retries": 3,
        "nocheckcertificate": True,
        "geo_bypass": True,
        "user_agent": random.choice(USER_AGENTS),
        "cookiefile": cookie_path,
        "http_headers": {
            "Referer": referer,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
        },
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)
            
            # ভিডিও ইউআরএল হ্যান্ডলিং
            download_url = info.get("url")
            if not download_url and "formats" in info:
                # সাউন্ড আছে এমন সেরা কোয়ালিটি MP4 খুঁজে বের করা
                valid_formats = [
                    f for f in info["formats"] 
                    if f.get("acodec") != "none" and f.get("vcodec") != "none"
                ]
                if valid_formats:
                    valid_formats.sort(key=lambda x: (x.get("height") or 0), reverse=True)
                    download_url = valid_formats[0]["url"]

            if download_url:
                result = {
                    "status": "success",
                    "url": download_url,
                    "title": info.get("title", "Video"),
                    "thumbnail": info.get("thumbnail"), # থাম্বনেইল ফিক্স
                    "duration": info.get("duration"),
                    "source": info.get("extractor_key", domain)
                }

                with cache_lock:
                    cache[cache_key] = (result, time.time())
                    if len(cache) > 1000: cache.clear()
                
                return result

    except Exception as e:
        logging.error(f"Extraction Failed: {str(e)}")
        return None
    finally:
        # টেম্পোরারি কুকি ফাইল মুছে ফেলা (নিরাপত্তার জন্য)
        if cookie_path and os.path.exists(cookie_path):
            try: os.remove(cookie_path)
            except: pass

# -----------------------------
# ROUTES
# -----------------------------
@app.get("/get_media")
async def get_media(url: str, request: Request):
    # API KEY ভেরিফিকেশন
    api_key = request.headers.get("x-api-key")
    if not api_key or api_key not in VALID_API_KEYS:
        raise HTTPException(status_code=401, detail="Unauthorized")

    # রেট লিমিট চেক
    now = time.time()
    user_rates = rate_store.get(api_key, [])
    user_rates = [t for t in user_rates if now - t < RATE_WINDOW]
    if len(user_rates) >= RATE_LIMIT:
        raise HTTPException(status_code=429, detail="Too many requests")
    user_rates.append(now)
    rate_store[api_key] = user_rates

    if not url: raise HTTPException(status_code=400, detail="URL missing")

    url = clean_url(url)
    if not is_valid_url(url):
        raise HTTPException(status_code=400, detail="Unsupported Website")

    try:
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(executor, extract_media, url)

        if not result:
            raise HTTPException(status_code=404, detail="Could not extract media. Check cookies/url.")

        return result
    except Exception as e:
        logging.error(f"Server Error: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal Server Error")

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)