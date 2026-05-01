# Use a specific slim version for stability
FROM python:3.10-slim

# Set environment variables for better Python performance
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000

# Install system dependencies in one layer to keep image size small
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user for security (Essential for Production)
RUN groupadd -g 999 appuser && \
    useradd -r -u 999 -g appuser appuser

WORKDIR /app

# Install Python dependencies separately to leverage Docker layer caching
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir -U yt-dlp

# Copy project files
COPY . .

# Create and set permissions for temp folder (used by ffmpeg)
RUN mkdir -p /app/temp && \
    chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Run server with Gunicorn
CMD gunicorn -w 4 -k uvicorn.workers.UvicornWorker server:app --bind 0.0.0.0:${PORT}