from flask import Flask, request, jsonify
from flask_cors import CORS
import yt_dlp

# এখানে অবশ্যই double underscore (_name_)
app = Flask(__name__)
CORS(app)

@app.route('/get_video', methods=['GET'])
def get_video():
    video_url = request.args.get('url')

    if not video_url:
        return jsonify({
            "status": "error",
            "message": "No URL provided"
        }), 400

    ydl_opts = {
        'format': 'best[ext=mp4]',
        'quiet': True
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(video_url, download=False)

            # safe way to get video URL
            formats = info.get('formats', [])
            best_format = formats[-1] if formats else {}

            return jsonify({
                "status": "success",
                "url": best_format.get('url'),
                "title": info.get('title')
            })

    except Exception:
        return jsonify({
            "status": "error",
            "message": "Failed to fetch video"
        }), 400


# এখানেও double underscore (_name_)
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
