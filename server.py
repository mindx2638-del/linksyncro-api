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

    ydl_opts = {
        'format': 'best',
        'quiet': True,
        'no_warnings': True,
        'noplaylist': True,
        # এই অংশটি ইউটিউবকে বিশ্বাস করাবে যে এটি একটি আসল ব্রাউজার
        'user_agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(video_url, download=False)
            download_url = info.get('url') or info.get('formats')[0].get('url')
            
            return jsonify({
                "status": "success",
                "url": download_url,
                "title": info.get('title', 'Video')
            })
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 400

if __name__ == '_main_':
    app.run(host='0.0.0.0', port=5000)