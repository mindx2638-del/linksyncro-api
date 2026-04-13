FROM python:3.10-slim

# FFmpeg ইনস্টল করা
RUN apt-get update && apt-get install -y ffmpeg && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# এই লাইনে server:app ব্যবহার করবেন
CMD ["gunicorn", "-w", "4", "-k", "uvicorn.workers.UvicornWorker", "server:app", "--bind", "0.0.0.0:10000"]