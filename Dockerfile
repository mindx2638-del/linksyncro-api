FROM python:3.10-slim

# FFmpeg ইনস্টল করা
RUN apt-get update && apt-get install -y ffmpeg && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# পোর্টের জায়গায় $PORT ব্যবহার করতে হবে এবং sh -c কমান্ড দিয়ে এটি রান করতে হবে
CMD sh -c "gunicorn -w 4 -k uvicorn.workers.UvicornWorker server:app --bind 0.0.0.0:$PORT"