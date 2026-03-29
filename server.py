from flask import Flask, request, jsonify
from flask_cors import CORS
import yt_dlp

app = Flask(_name_)
CORS(app)

@app.route('/get_video', methods=['GET'])
def get_video():
    video_url = request.args.get('url')
    if not video_url:
        return jsonify({"status": "error", "message": "No URL provided"}), 400

    # অডিওসহ ভিডিও এবং থাম্বনেইল পাওয়ার জন্য আপডেট করা অপশন
    ydl_opts = {
        # 'best' এর বদলে এই ফরম্যাটটি অডিওসহ ভিডিও (Muxed) নিশ্চিত করবে
        'format': 'best[ext=mp4]/best', 
        'quiet': True,
        'no_warnings': True,
        'noplaylist': True,
        'user_agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(video_url, download=False)
            
            # ডাউনলোড ইউআরএল গেট করা
            download_url = info.get('url')
            
            # যদি 'url' সরাসরি না পাওয়া যায়, তবে ফরম্যাট লিস্ট থেকে নেওয়া
            if not download_url and 'formats' in info:
                for f in info['formats']:
                    # এমন লিঙ্ক খোঁজা যেখানে অডিও এবং ভিডিও দুটোই আছে (acodec != none)
                    if f.get('acodec') != 'none' and f.get('vcodec') != 'none':
                        download_url = f.get('url')
                        break

            return jsonify({
                "status": "success",
                "url": download_url,
                "title": info.get('title', 'Video'),
                "thumbnail": info.get('thumbnail'), # থাম্বনেইল লিঙ্কটি এখানে যোগ করা হয়েছে
                "duration": info.get('duration')
            })
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 400

if _name_ == '_main_':
    # Render বা অন্য কোথাও হোস্ট করলে পোর্ট এনভায়রনমেন্ট ভেরিয়েবল থেকে নিতে হয়
    import os
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port)