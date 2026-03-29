from flask import Flask, request, jsonify
from flask_cors import CORS
import yt_dlp
import os

app = Flask(__name__)
CORS(app)

@app.route('/get_video', methods=['GET'])
def get_video():
    video_url = request.args.get('url')
    if not video_url:
        return jsonify({"status": "error", "message": "No URL provided"}), 400

    # অডিওসহ ভিডিও নিশ্চিত করার জন্য উন্নত ফরম্যাট লজিক
    ydl_opts = {
        # acodec!=none মানে অডিও থাকতে হবে, vcodec!=none মানে ভিডিও থাকতে হবে
        'format': 'best[vcodec!=none][acodec!=none]/best',
        'quiet': True,
        'no_warnings': True,
        'noplaylist': True,
        'user_agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(video_url, download=False)
            
            # অডিওসহ ডাউনলোড ইউআরএল ফিল্টার করা
            download_url = info.get('url')
            if not download_url and 'formats' in info:
                # এমন ফরম্যাট খোঁজা যেখানে অডিও এবং ভিডিও দুটোই আছে
                muxed_formats = [f for f in info['formats'] if f.get('acodec') != 'none' and f.get('vcodec') != 'none']
                if muxed_formats:
                    # সবচেয়ে ভালো কোয়ালিটির ফাইলটি নেওয়া
                    download_url = muxed_formats[-1].get('url')

            return jsonify({
                "status": "success",
                "url": download_url,
                "title": info.get('title', 'Facebook Video'),
                "thumbnail": info.get('thumbnail'), # থাম্বনেইল পাঠানো হচ্ছে
                "source": info.get('extractor')
            })
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 400

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port)