from flask import Flask, request, jsonify
from flask_cors import CORS
import yt_dlp
import os

app = Flask(__name__)
CORS(app)

# ✅ Security check
def is_valid_url(url):
    return "youtube.com" in url or "youtu.be" in url

# ✅ Common yt-dlp options
def get_opts():
    return {
        'quiet': True,
        'no_warnings': True,
        'noplaylist': True,
    }

# 🔥 1. Get video info + all qualities
@app.route('/get_video_info', methods=['GET'])
def get_video_info():
    url = request.args.get('url')

    if not url:
        return jsonify({"status": "error", "message": "No URL provided"}), 400

    if not is_valid_url(url):
        return jsonify({"status": "error", "message": "Invalid URL"}), 400

    try:
        with yt_dlp.YoutubeDL(get_opts()) as ydl:
            info = ydl.extract_info(url, download=False)

            formats = []

            for f in info.get('formats', []):
                # Skip audio-only
                if f.get('vcodec') == 'none':
                    continue

                formats.append({
                    "format_id": f.get("format_id"),
                    "quality": f.get("format_note") or f.get("height"),
                    "ext": f.get("ext"),
                    "filesize": f.get("filesize"),
                    "has_audio": f.get("acodec") != "none"
                })

            # Sort highest quality first
            formats = sorted(formats, key=lambda x: (x['quality'] or 0), reverse=True)

            return jsonify({
                "status": "success",
                "title": info.get("title"),
                "thumbnail": info.get("thumbnail"),
                "formats": formats
            })

    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500


# 🔥 2. Get download link by selected quality
@app.route('/get_download', methods=['GET'])
def get_download():
    url = request.args.get('url')
    format_id = request.args.get('format_id')

    if not url or not format_id:
        return jsonify({"status": "error", "message": "Missing parameters"}), 400

    try:
        ydl_opts = {
            'format': f"{format_id}+bestaudio/best",
            'quiet': True,
            'noplaylist': True,
        }

        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)

            return jsonify({
                "status": "success",
                "download_url": info.get("url"),
                "title": info.get("title")
            })

    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500


# 🚀 Run server
if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port)