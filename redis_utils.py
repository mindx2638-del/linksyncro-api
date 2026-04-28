import redis
import json
import os
from dotenv import load_dotenv

load_dotenv()
# Redis কানেকশন
redis_client = redis.from_url(os.getenv("REDIS_URL"), decode_responses=True)

def get_cache(key):
    data = redis_client.get(f"cache:{key}")
    return json.loads(data) if data else None

def set_cache(key, value, ttl=1200):
    redis_client.set(f"cache:{key}", json.dumps(value), ex=ttl)

def check_rate_limit(api_key, limit, window):
    rate_key = f"rate:{api_key}"
    count = redis_client.incr(rate_key)
    if count == 1:
        redis_client.expire(rate_key, window)
    return count <= limit