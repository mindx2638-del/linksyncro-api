from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
import yt_dlp
import logging
import time
import ipaddress
import asyncio
import hashlib
import os
from urllib.parse import urlparse
from concurrent.futures import ThreadPoolExecutor

app = FastAPI()

# -----------------------------
# CORS (আপনার ডোমেইন অনুযায়ী আপডেট করুন)
# -----------------------------
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # প্রোডাকশনে আপনার নির্দিষ্ট ডোমেইন দিবেন
    allow_credentials=True,
    allow_methods=["GET"],
    allow_headers=["*"],
)

# -----------------------------
# LOGGING
# -----------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)

# -----------------------------
# THREAD POOL
# -----------------------------
executor = ThreadPoolExecutor(max_workers=10)

# -----------------------------
# CACHE & RATE LIMIT
# -----------------------------
cache = {}
CACHE_TTL = 300
rate_store = {}
RATE_LIMIT = 20
RATE_WINDOW = 60

# -----------------------------
# API KEYS
# -----------------------------
VALID_API_KEYS = {"demo_key_123", "premium_key_456"}

# -----------------------------
# ALLOWED DOMAINS
# -----------------------------
ALLOWED_DOMAINS = {
    "youtube.com", "www.youtube.com", "youtu.be", "m.youtube.com",
    "facebook.com", "www.facebook.com", "m.facebook.com", "fb.watch", "fb.com",
    "instagram.com", "www.instagram.com",
    "tiktok.com", "www.tiktok.com", "vm.tiktok.com"
}

# -----------------------------
# HELPERS
# -----------------------------
def is_private_ip(host):
    try:
        return ipaddress.ip_address(host).is_private
    except:
        return False

def is_valid_url(url: str):
    try:
        parsed = urlparse(url)
        if parsed.scheme not in ["http", "https"] or not parsed.hostname:
            return False
        if parsed.hostname in ["localhost", "127.0.0.1"] or is_private_ip(parsed.hostname):
            return False
        # ডোমেইন চেক (সাবডোমেইন সাপোর্ট সহ)
        domain_parts = parsed.hostname.split('.')
        base_domain = ".".join(domain_parts[-2:]) if len(domain_parts) > 1 else parsed.hostname
        return base_domain in ["youtube.com", "youtu.be", "facebook.com", "fb.com", "fb.watch", "instagram.com", "tiktok.com"]
    except:
        return False

# -----------------------------
# CORE ENGINE (Facebook Fixed)
# -----------------------------
def extract_media(url: str):
    cache_key = hashlib.md5(url.encode()).hexdigest()
    if cache_key in cache:
        data, ts = cache[cache_key]
        if time.time() - ts < CACHE_TTL:
            return data

    # কুকি ফাইল চেক (আপনার ফোল্ডারে এই ফাইলটি রাখতে হবে)
    cookie_path = "facebook_cookies.txt"
    
    ydl_opts = {
        "format": "best",
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "socket_timeout": 20,
        "retries": 5,
        "user_agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36",
        "http_headers": {
            "Referer": "https://www.facebook.com/",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        }
    }

    # যদি কুকি ফাইল থাকে তবে সেটি ব্যবহার করবে
    if os.path.exists(cookie_path):
        ydl_opts["cookiefile"] = cookie_path
        logging.info("Using cookies for extraction")

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)
            download_url = info.get("url")

            if not download_url and "formats" in info:
                # ভিডিও কোয়ালিটি ফিল্টার
                formats = [f for f in info["formats"] if f.get("url") and f.get("vcodec") != "none"]
                formats.sort(key=lambda x: (x.get("height") or 0), reverse=True)
                if formats:
                    download_url = formats[0]["url"]

            if not download_url:
                return None

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
        result = await loop.run_in_executor(executor, extract_media, url)

        if not result:
            # যদি প্রথমবার ব্যর্থ হয়, কুকি ছাড়াও একবার ট্রাই করতে পারে
            raise HTTPException(status_code=404, detail="Could not extract video. It might be private or region-locked.")

        return result
    except HTTPException as he:
        raise he
    except Exception as e:
        logging.error(f"Server Error: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")