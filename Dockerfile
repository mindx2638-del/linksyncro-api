FROM python:3.10-slim

# system dependencies
RUN apt-get update && apt-get install -y \
    ffmpeg \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# default port fallback (IMPORTANT FIX)
ENV PORT=8000

# run server safely
CMD sh -c "gunicorn -w 4 -k uvicorn.workers.UvicornWorker server:app --bind 0.0.0.0:${PORT}"