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
app = FastAPI(title="LinkSyncro Media API", version="2.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["GET"],
    allow_headers=["*"],
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
executor = ThreadPoolExecutor(max_workers=20)

# -----------------------------
# CACHE & SETTINGS
# -----------------------------
cache = {}
CACHE_TTL = 1200 
rate_store = {}
RATE_LIMIT = 50
RATE_WINDOW = 60
VALID_API_KEYS = {"demo_key_123", "premium_key_456"}

USER_AGENTS = [
    # TikTok Official Android App Agent (Priority)
    "com.zhiliaoapp.musically/2022405010 (Linux; U; Android 12; en_US; Pixel 5; Build/S1B2.210901.041; Cronet/58.0.2991.0)",
    "Mozilla/5.0 (Linux; Android 13; SM-S911B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Mobile Safari/537.36",
    "Mozilla/5.0 (iPad; CPU OS 16_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Mobile/15E148 Safari/604.1"
]

# -----------------------------
# HELPERS
# -----------------------------
def is_valid_url(url: str):
    try:
        parsed = urlparse(url)
        if parsed.scheme not in ["http", "https"] or not parsed.hostname:
            return False
        domain = parsed.hostname.lower().replace("www.", "")
        allowed = [
            "youtube.com", "youtu.be", 
            "facebook.com", "fb.watch", "fb.com", 
            "instagram.com", 
            "tiktok.com", "vt.tiktok.com", "vm.tiktok.com"
        ]
        return any(d in domain for d in allowed)
    except:
        return False

def get_cookie_files(domain):
    """ডোমেইন অনুযায়ী সঠিক ফোল্ডার থেকে সব .txt কুকি ফাইল রিটার্ন করবে"""
    folder_map = {
        "facebook": "facebook_cookies",
        "fb": "facebook_cookies",
        "youtube": "youtube_cookies",
        "youtu.be": "youtube_cookies",
        "instagram": "instagram_cookies",
        "tiktok": "tiktok_cookies",
        "vt.tiktok": "tiktok_cookies",
        "vm.tiktok": "tiktok_cookies"
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
    # ১. ক্যাশ চেক
    cache_key = hashlib.md5(url.encode()).hexdigest()
    if cache_key in cache:
        data, ts = cache[cache_key]
        if time.time() - ts < CACHE_TTL:
            logging.info(f"Cache Hit: {url}")
            return data

    domain = urlparse(url).hostname or ""
    # টিকটকের জন্য ডোমেইন চেক (শর্ট লিঙ্কসহ)
    is_tiktok = any(d in domain for d in ["tiktok.com", "vt.tiktok", "vm.tiktok"])
    
    # কুকি লিস্ট (প্রথমে কুকি ছাড়া, তারপর কুকি দিয়ে চেষ্টা)
    cookie_list = [None] 
    cookie_list.extend(get_cookie_files(domain))

    for cookie_path in cookie_list:
        ydl_opts = {
            "format": "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
            "quiet": True,
            "no_warnings": True,
            "noplaylist": True,
            "socket_timeout": 60, # টাইমআউট একটু বাড়ানো হয়েছে
            "retries": 10,       # রিট্রাই বাড়ানো হয়েছে
            "nocheckcertificate": True,
            "geo_bypass": True,
            "user_agent": random.choice(USER_AGENTS),
            "http_headers": {
                "Accept": "*/*",
                "Accept-Language": "en-US,en;q=0.9",
                # টিকটকের জন্য প্রোপার রেফারার
                "Referer": "https://www.tiktok.com/" if is_tiktok else "https://www.google.com/",
            },
            "extractor_args": {
                "youtube": {
                    "player_client": ["android", "ios", "mweb"], 
                    "player_skip": ["webpage", "configs"]
                },
                "instagram": {
                    "player_client": ["android", "ios", "mweb"]
                },
                "facebook": {
                    "player_client": ["android", "ios", "mweb"]
                },
                "tiktok": {
                    "app_name": "google_play", 
                    "is_test": False,
                    "player_client": ["android", "ios", "mweb"]
                }
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
                
                download_url = None
                
                # ১. সরাসরি URL চেক এবং ৪MD৩ ফিল্টার
                temp_url = info.get("url")
                if temp_url and "403" not in temp_url:
                    download_url = temp_url

                # ২. যদি সরাসরি না পাওয়া যায়, তবে ফরম্যাট লিস্ট চেক
                if not download_url and "formats" in info:
                    # mp4 এবং অডিও আছে এমন ফরম্যাট খোঁজা
                    valid_formats = [
                        f for f in info["formats"] 
                        if f.get("url") and f.get("vcodec") != "none" and f.get("acodec") != "none"
                    ]
                    
                    if not valid_formats:
                        valid_formats = [f for f in info["formats"] if f.get("url") and "403" not in f.get("url")]

                    if valid_formats:
                        # সেরা রেজোলিউশন আগে রাখা
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
                          "headers": {
                            "User-Agent": "com.zhiliaoapp.musically/2022405010 (Linux; U; Android 12; en_US; Pixel 5; Build/S1B2.210901.041; Cronet/58.0.2991.0)",
                            "Referer": "https://www.tiktok.com/" if is_tiktok else "https://www.google.com/",
                        }

                    }
                    
                    cache[cache_key] = (result, time.time())
                    if len(cache) > 1000:
                        cache.pop(next(iter(cache)))
                    
                    return result
                    
        except Exception as e:
            logging.error(f"Error with {cookie_path or 'No Cookie'}: {str(e)}")
            continue 

    return None

# -----------------------------
# ROUTES
# -----------------------------
@app.get("/get_media")
async def get_media(url: str, request: Request):
    # API Key Check
    key = request.headers.get("x-api-key")
    if not key or key not in VALID_API_KEYS:
        raise HTTPException(status_code=401, detail="Unauthorized: Invalid API Key")

    # Rate Limit Check
    now = time.time()
    user_rates = rate_store.get(key, [])
    user_rates = [t for t in user_rates if now - t < RATE_WINDOW]
    rate_store[key] = user_rates
    if len(user_rates) >= RATE_LIMIT:
        raise HTTPException(status_code=429, detail="Rate limit exceeded")
    rate_store[key].append(now)

    if not url:
        raise HTTPException(status_code=400, detail="URL is required")

    # URL ক্লিনিং
    if "?" in url and ("facebook" in url or "fb" in url or "instagram" in url):
        url = url.split("?")[0]

    if not is_valid_url(url):
        raise HTTPException(status_code=400, detail="Unsupported or invalid URL")

    try:
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(executor, extract_media, url)
        if not result:
            raise HTTPException(status_code=404, detail="Could not extract video. Content may be private or IP blocked.")
        return result
    except HTTPException as he:
        raise he
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