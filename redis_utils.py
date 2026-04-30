import redis
import json
import os
import logging
from typing import Any, Optional
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Logger setup (essential for debugging)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Redis connection setup
REDIS_URL = os.getenv("REDIS_URL")

if not REDIS_URL:
    logger.critical("REDIS_URL environment variable not found!")
    raise ValueError("REDIS_URL must be configured.")

try:
    # Using connection pool suitable for serverless environments
    redis_client = redis.from_url(REDIS_URL, decode_responses=True)
    redis_client.ping() # Connection check
    logger.info("Redis connected successfully.")
except redis.RedisError as e:
    logger.error(f"Redis connection error: {e}")
    redis_client = None

def get_cache(key: str) -> Optional[Any]:
    """Professional function to retrieve data from Redis"""
    if not redis_client:
        return None
    try:
        data = redis_client.get(f"cache:{key}")
        if data:
            return json.loads(data)
    except (redis.RedisError, json.JSONDecodeError) as e:
        logger.error(f"Cache get error for {key}: {e}")
    return None

def set_cache(key: str, value: Any, ttl: int = 1200) -> bool:
    """Professional function to save data to Redis"""
    if not redis_client:
        return False
    try:
        serialized_data = json.dumps(value)
        redis_client.set(f"cache:{key}", serialized_data, ex=ttl)
        return True
    except (redis.RedisError, TypeError) as e:
        logger.error(f"Cache set error for {key}: {e}")
        return False

def check_rate_limit(api_key: str, limit: int, window: int) -> bool:
    """Secure function to check rate limit"""
    if not redis_client:
        return True # If Redis is down, we allow operations to continue
    
    rate_key = f"rate:{api_key}"
    try:
        count = redis_client.incr(rate_key)
        if count == 1:
            redis_client.expire(rate_key, window)
        return count <= limit
    except redis.RedisError as e:
        logger.error(f"Rate limit error: {e}")
        return True
