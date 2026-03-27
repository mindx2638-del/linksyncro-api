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

    # ৪কে ডাউনলোডারের মতো 'Anti-Block' অপশনস
    ydl_opts = {
        'format': 'best',
        'quiet': True,
        'no_warnings': True,
        'noplaylist': True,
        # এই হেডারগুলো থাকলে ইউটিউব মনে করবে এটি আসল ব্রাউজার
        'user_agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
        'referer': 'https://www.google.com/',
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            # তথ্য বের করা
            info = ydl.extract_info(video_url, download=False)
            
            # রেজাল্ট পাঠানো
            return jsonify({
                "status": "success",
                "title": info.get('title', 'Video'),
                "url": info.get('url') or (info.get('formats')[0].get('url') if info.get('formats') else None),
                "thumbnail": info.get('thumbnail'),
                "duration": info.get('duration')
            })
    except Exception as e:
        # এরর হলে পরিষ্কার মেসেজ পাঠানো
        return jsonify({"status": "error", "message": str(e)}), 400

# এখানে স্পেলিং মিস্টেক ( __name__ ) ঠিক করা হয়েছে
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)