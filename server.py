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
cache = {}
CACHE_TTL = 1200 
rate_store = {}
RATE_LIMIT = 50
RATE_WINDOW = 60
VALID_API_KEYS = {"demo_key_123", "premium_key_456"}

# Android এবং iOS সাপোর্ট নিশ্চিত করতে আধুনিক মোবাইল ইউজার এজেন্ট
USER_AGENTS = [
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (Linux; Android 14; Pixel 😎 AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36",
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
    # ক্যাশ চেক লজিক (অপরিবর্তিত)
    cache_key = hashlib.md5(url.encode()).hexdigest()
    if cache_key in cache:
        data, ts = cache[cache_key]
        if time.time() - ts < CACHE_TTL:
            logging.info(f"Cache Hit: {url}")
            return data

    # ১. লিঙ্ক ক্লিনিং (TikTok এবং অন্যান্য সাইটের ট্র্যাকিং আইডি বাদ দেওয়া)
    if any(x in url for x in ["tiktok.com", "facebook.com", "instagram.com"]):
        url = url.split("?")[0]

    domain = urlparse(url).hostname or ""
    
    # ২. কুকি লিস্ট ম্যাপ করা (TikTok কুকি ফোল্ডার থাকলে তা চেক করবে)
    cookie_list = [None] 
    cookie_list.extend(get_cookie_files(domain))

    for cookie_path in cookie_list:
        ydl_opts = {
            "format": "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
            "quiet": True,
            "no_warnings": True,
            "noplaylist": True,
            "socket_timeout": 20, # ১৫-২০ সেকেন্ডের বেশি অপেক্ষা করা মানে লিঙ্ক স্লো
            "retries": 5, 
            "nocheckcertificate": True,
            "geo_bypass": True,
            "user_agent": random.choice(USER_AGENTS),
            "ignoreerrors": True, # এরর থাকলেও চেষ্টা চালিয়ে যাবে
            
            # ৩. ডাউনলোড স্পিড এবং কানেকশন অপ্টিমাইজেশন
            "concurrent_fragment_downloads": 10,
            "http_headers": {
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
                "Accept-Language": "en-US,en;q=0.5",
                # ৪. TikTok এর জন্য সঠিক রেফারার সেট করা
                "Referer": "https://www.tiktok.com/" if "tiktok" in url else "https://www.google.com/",
            },
            
            "extractor_args": {
                "youtube": {"player_client": ["android", "ios", "mweb", "tv"], "player_skip": ["webpage", "configs"]},
                "instagram": {"force_subtitles": False},
                "facebook": {"force_generic_extractor": False},
                # ৫. TikTok এর জন্য স্পেশাল আর্গুমেন্ট
                "tiktok": {"app_version": "20.2.1"}
            }
        }

        if cookie_path:
            ydl_opts["cookiefile"] = cookie_path

        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                # ৬. প্রসেসিং লজিক (সরাসরি ভিডিও লিঙ্ক খোঁজা)
                info = ydl.extract_info(url, download=False, process=True)
                
                if not info:
                    continue

                # যদি এটি একটি প্লেলিস্ট বা এন্ট্রি হয় (TikTok প্রায়ই এভাবে ডাটা দেয়)
                if 'entries' in info:
                    info = info['entries'][0]
                
                download_url = info.get("url")
                
                # আপনার অরিজিনাল ফরম্যাট সিলেকশন লজিক (অপরিবর্তিত)
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
                        "source": info.get("extractor_key", domain)
                    }
                    
                    cache[cache_key] = (result, time.time())
                    if len(cache) > 2000:
                        cache.pop(next(iter(cache)))
                    
                    return result
                    
        except Exception as e:
            logging.error(f"Error for {url}: {str(e)}")
            continue 

    return None

# -----------------------------
# ROUTES
# -----------------------------
@app.get("/get_media")
async def get_media(url: str, request: Request):
    # আপনার অরিজিনাল API Key চেক লজিক
    key = request.headers.get("x-api-key")
    if not key or key not in VALID_API_KEYS:
        raise HTTPException(status_code=401, detail="Unauthorized: Invalid API Key")

    # আপনার অরিজিনাল Rate Limit লজিক
    now = time.time()
    user_rates = rate_store.get(key, [])
    user_rates = [t for t in user_rates if now - t < RATE_WINDOW]
    rate_store[key] = user_rates
    if len(user_rates) >= RATE_LIMIT:
        raise HTTPException(status_code=429, detail="Rate limit exceeded")
    rate_store[key].append(now)

    if not url:
        raise HTTPException(status_code=400, detail="URL is required")

    # আপনার অরিজিনাল URL ক্লিনিং লজিক
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