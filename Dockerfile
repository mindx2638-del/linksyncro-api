# Use a specific slim version for stability
FROM python:3.10-slim

# Set environment variables for better Python performance
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=10000

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user (Security preserved)
RUN groupadd -g 999 appuser && \
    useradd -r -u 999 -g appuser -m appuser

WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir -U yt-dlp

# Copy project files
COPY . .

# Create temp folder and fix ALL permissions for appuser
# রেন্ডারের পারমিশন এরর এড়াতে পুরো /app এবং হোম ডিরেক্টরি পারমিশন দেওয়া হয়েছে
RUN mkdir -p /app/temp && \
    chown -R appuser:appuser /app && \
    chmod -R 777 /app && \
    chown -R appuser:appuser /home/appuser

# Switch to non-root user
USER appuser

# Run server with Gunicorn (Port and Binding fixed)
# রেন্ডারে সরাসরি $PORT ভেরিয়েবল ব্যবহার করা নিরাপদ
CMD gunicorn -w 4 -k uvicorn.workers.UvicornWorker server:app --bind 0.0.0.0:${PORT} --timeout 120