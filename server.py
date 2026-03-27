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
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(video_url, download=False)
            download_url = info.get('url') or info.get('formats')[0].get('url')
            title = info.get('title', 'Video')

            return jsonify({
                "status": "success",
                "url": download_url,
                "title": title
            })
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 400

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)