from flask import Flask, request, jsonify
from flask_cors import CORS
import yt_dlp
import os

app = Flask(_name_)
CORS(app)

@app.route('/get_video', methods=['GET'])
def get_video():
    video_url = request.args.get('url')
    if not video_url:
        return jsonify({"status": "error", "message": "No URL provided"}), 400

    # অডিওসহ ভিডিও নিশ্চিত করার জন্য এবং ইউটিউব/ফেসবুক ব্লক এড়ানোর জন্য কনফিগারেশন
    ydl_opts = {
        # 'best' এর সাথে acodec এবং vcodec চেক করা হয়েছে যাতে সাউন্ড মিস না হয়
        'format': 'best[vcodec!=none][acodec!=none]/best',
        'quiet': True,
        'no_warnings': True,
        'noplaylist': True,
        # ব্রাউজার হেডার যাতে সাইটগুলো বট হিসেবে ডিটেক্ট না করে
        'user_agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            # ভিডিওর তথ্য বের করা
            info = ydl.extract_info(video_url, download=False)
            
            download_url = None

            # ১. সরাসরি ইউআরএল চেক করা
            if info.get('url'):
                download_url = info.get('url')
            
            # ২. যদি সরাসরি না পাওয়া যায়, তবে ফরম্যাট লিস্ট থেকে সেরা Muxed লিঙ্ক খোঁজা
            elif 'formats' in info:
                # এমন সব ফরম্যাট ফিল্টার করা যেখানে অডিও এবং ভিডিও দুটোই আছে
                muxed_formats = [
                    f for f in info['formats'] 
                    if f.get('acodec') != 'none' and f.get('vcodec') != 'none' and f.get('url')
                ]
                if muxed_formats:
                    # সবচেয়ে হাই-কোয়ালিটির (লিস্টের শেষের দিকে থাকে) লিঙ্কটি নেওয়া
                    download_url = muxed_formats[-1].get('url')

            if not download_url:
                return jsonify({"status": "error", "message": "Could not find a valid video with audio"}), 404

            return jsonify({
                "status": "success",
                "url": download_url,
                "title": info.get('title', 'Social Media Video'),
                "thumbnail": info.get('thumbnail'), # থাম্বনেইল ডাটা
                "duration": info.get('duration'),
                "source": info.get('extractor_key')
            })

    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 400

if _name_ == '_main_':
    # Render বা পোর্টেবল হোস্টিং এর জন্য পোর্ট ম্যানেজমেন্ট
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port)
You sent
import 'dart:convert';
import 'package:http/http.dart' as http;

class YouTubeService {
  static const String _apiUrl = "https://linksyncro-api-1.onrender.com/get_video";

  bool isYouTubeLink(String url) => url.contains("youtube.com") || url.contains("youtu.be");

  Future<Map<String, String>> getVideoDetails(String url) async {
    try {
      // লিঙ্কটি ক্লিন করে এনকোড করা
      final cleanUrl = url.trim();
      final response = await http.get(
        Uri.parse("$_apiUrl?url=${Uri.encodeComponent(cleanUrl)}"),
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          return {
            'url': data['url'].toString(),
            'title': data['title'].toString(),
            'thumbnail': data['thumbnail']?.toString() ?? "",
          };
        }
      }
      throw "Failed to fetch video data";
    } catch (e) {
      throw "Error: $e";
    }
  }
}