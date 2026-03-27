from flask import Flask, request, jsonify
from flask_cors import CORS
import yt_dlp

app = Flask(__name__)
CORS(app)

@app.route('/get_video', methods=['GET'])
def get_video():
    video_url = request.args.get('url')
    if not video_url:
        return jsonify({"status": "error", "message": "No URL provided"}), 400

    # ৪কে ডাউনলোডারের মতো অ্যাডভান্সড অপশনস
    ydl_opts = {
        'format': 'best', # সরাসরি অডিও-ভিডিও যুক্ত সেরা কোয়ালিটি নিবে
        'quiet': True,
        'no_warnings': True,
        'noplaylist': True,
        'user_agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
        'referer': 'https://www.google.com/', # ইউটিউব মনে করবে গুগল থেকে আসা ট্রাফিক
        'http_headers': {
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'en-us,en;q=0.5',
        }
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            # ভিডিও এক্সট্রাক্ট করা
            info = ydl.extract_info(video_url, download=False)
            
            # ডাটা পাঠানো (থাম্বনেইলসহ)
            return jsonify({
                "status": "success",
                "title": info.get('title', 'Video'),
                "url": info.get('url'),
                "thumbnail": info.get('thumbnail'), # অ্যাপে ছবি দেখানোর জন্য
                "duration": info.get('duration'),
                "source": info.get('extractor_key')
            })
    except Exception as e:
        # এরর মেসেজ ক্লিন করে পাঠানো
        return jsonify({"status": "error", "message": "Link blocked or invalid"}), 400

# এখানে স্পেলিং ঠিক করা হয়েছে
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)