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

# ২০ জন কর্মী সেট করা হয়েছে হাই-ট্রাফিক হ্যান্ডেল করতে
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
        if parsed.scheme not in ["http", "https"] or not parsed.hostname:
            return False
        domain = parsed.hostname.replace("www.", "")
        allowed = ["youtube.com", "youtu.be", "facebook.com", "fb.watch", "fb.com", "instagram.com", "tiktok.com"]
        return any(d in domain for d in allowed)
    except:
        return False

# -----------------------------
# CORE ENGINE
# -----------------------------
def extract_media(url: str):
    # ১. ক্যাশ চেক (আপনার আগের লজিক অনুযায়ী)
    cache_key = hashlib.md5(url.encode()).hexdigest()
    if cache_key in cache:
        data, ts = cache[cache_key]
        if time.time() - ts < CACHE_TTL:
            logging.info(f"Cache Hit: {url}")
            return data

    # ২. কুকি ফাইল পাথ
    fb_cookies = "facebook_cookies.txt"
    yt_cookies = "youtube_cookies.txt"
    ig_cookies = "www.instagram.com_cookies.txt" 

    # ৩. yt-dlp কনফিগারেশন (রেজোলিউশন লিস্ট পাওয়ার জন্য আপডেট করা)
    ydl_opts = {
        "format": "best", # সব ফরম্যাট দেখার জন্য
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
            "Referer": "https://www.google.com/",
        },
        "extractor_args": {
            "youtube": {
                "player_client": ["android", "ios", "mweb"],
                "player_skip": ["webpage", "configs"]
            },
            "instagram": {"force_subtitles": False}
        }
    }

    # ৪. ডোমেইন অনুযায়ী কুকি সিলেকশন (আপনার অরিজিনাল লজিক)
    domain = urlparse(url).hostname or ""
    if any(d in domain for d in ["facebook.com", "fb.watch", "fb.com"]):
        if os.path.exists(fb_cookies): 
            ydl_opts["cookiefile"] = fb_cookies
            logging.info("Applying FB Cookies")
    elif any(d in domain for d in ["youtube.com", "youtu.be"]):
        if os.path.exists(yt_cookies): 
            ydl_opts["cookiefile"] = yt_cookies
            logging.info("Applying YT Cookies")
    elif "instagram.com" in domain:
        ydl_opts["http_headers"]["Referer"] = "https://www.instagram.com/"
        if os.path.exists(ig_cookies): 
            ydl_opts["cookiefile"] = ig_cookies
            logging.info(f"Applying Instagram Cookies")

    # ৫. এক্সট্রাকশন লজিক
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)
            formats = info.get("formats", [])
            
            video_options = []
            seen_resolutions = set()

            # লো থেকে হাই রেজোলিউশন (৩৬০পি - ৪কে/৮কে) ফিল্টার করা
            for f in formats:
                # যেসব ফরম্যাটে অডিও ও ভিডিও উভয়ই আছে এবং হাইট পাওয়া যাচ্ছে
                if f.get('vcodec') != 'none' and f.get('height'):
                    height = f.get('height')
                    
                    # ৩৬০পি এর নিচের গুলো বাদ (লো কোয়ালিটি এড়াতে)
                    if height < 360: continue

                    # রেজোলিউশন লেবেল তৈরি (৩৬০পি, ৪কে, ৮কে)
                    res_label = f"{height}p"
                    if height == 2160: res_label = "4K"
                    elif height == 4320: res_label = "8K"

                    # একই রেজোলিউশন ডুপ্লিকেট এড়ানো
                    if res_label not in seen_resolutions:
                        video_options.append({
                            "quality": res_label,
                            "url": f.get('url'),
                            "ext": f.get('ext', 'mp4'),
                            "size": f.get('filesize') or f.get('filesize_approx')
                        })
                        seen_resolutions.add(res_label)

            # রেজোলিউশন অনুযায়ী ছোট থেকে বড় সাজানো
            video_options.sort(key=lambda x: int(''.join(filter(str.isdigit, x['quality']))) if any(c.isdigit() for c in x['quality']) else 0)

            # যদি কোনো অপশন না পাওয়া যায়, তবে ডিফল্ট সেরা ইউআরএলটি নেওয়া
            download_url = info.get("url")
            if not video_options and download_url:
                 video_options.append({"quality": "Default", "url": download_url, "ext": "mp4"})

            if not video_options:
                return None

            result = {
                "status": "success",
                "title": info.get("title", "Video"),
                "thumbnail": info.get("thumbnail"),
                "duration": info.get("duration"),
                "source": info.get("extractor_key", domain),
                "formats": video_options # ফ্ল্যাটার এই লিস্টটি ব্যবহার করবে
            }
            
            # ক্যাশ স্টোরেজ (আপনার অরিজিনাল লজিক)
            cache[cache_key] = (result, time.time())
            if len(cache) > 1000:
                cache.pop(next(iter(cache)))
                
            return result
            
    except Exception as e:
        logging.error(f"yt-dlp error for {url}: {str(e)}")
        return None

# -----------------------------
# ROUTES
# -----------------------------
@app.get("/get_media")
async def get_media(url: str, request: Request):
    key = request.headers.get("x-api-key")
    if not key or key not in VALID_API_KEYS:
        raise HTTPException(status_code=401, detail="Unauthorized: Invalid API Key")

    now = time.time()
    user_rates = rate_store.get(key, [])
    user_rates = [t for t in user_rates if now - t < RATE_WINDOW]
    rate_store[key] = user_rates
    if len(user_rates) >= RATE_LIMIT:
        raise HTTPException(status_code=429, detail="Rate limit exceeded")
    rate_store[key].append(now)

    if not url:
        raise HTTPException(status_code=400, detail="URL is required")
        
    # ইউআরএল ক্লিন করা
    if "?" in url and ("facebook" in url or "instagram" in url):
        url = url.split("?")[0]

    if not is_valid_url(url):
        raise HTTPException(status_code=400, detail="Unsupported or invalid URL")

    try:
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(executor, extract_media, url)
        
        if not result:
            raise HTTPException(status_code=404, detail="Could not extract video. Check cookies or URL privacy.")
        
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
