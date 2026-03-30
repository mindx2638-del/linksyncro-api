import 'dart:convert';
import 'package:http/http.dart' as http;

class FacebookService {
  // আপনার API URL (নিশ্চিত করুন আপনার FastAPI-তে '/get_media' এন্ডপয়েন্টটি ঠিক আছে কি না)
  // আপনার আগের কোডে '/get_video' ছিল, কিন্তু FastAPI কোডে আমরা '/get_media' ব্যবহার করেছি।
  static const String _apiUrl = "https://linksyncro-api-1.onrender.com/get_media";
  
  // আপনার এপিআই কি (FastAPI কোডে দেওয়া কি-এর সাথে মিল থাকতে হবে)
  static const String _apiKey = "demo_key_123"; 

  // সব ধরনের ফেসবুক লিঙ্ক শনাক্ত করার উন্নত লজিক
  bool isFacebookLink(String url) {
    String lowerUrl = url.toLowerCase();
    return lowerUrl.contains("facebook.com") || 
           lowerUrl.contains("fb.watch") || 
           lowerUrl.contains("fb.com");
  }

  Future<Map<String, String>> getVideoDetails(String url) async {
    try {
      // ১. ইউআরএল ক্লিনিং লজিক আপডেট: 
      // ফেসবুক রিলস বা নির্দিষ্ট কিছু ভিডিওর জন্য প্যারামিটার প্রয়োজন হয়।
      // তাই সরাসরি অরিজিনাল লিঙ্কটি ব্যবহার করাই নিরাপদ।
      String targetUrl = url.trim();

      // ২. এপিআই কল (Headers এ API Key সহ)
      final response = await http.get(
        Uri.parse("$_apiUrl?url=${Uri.encodeComponent(targetUrl)}"),
        headers: {
          "x-api-key": _apiKey,
          "Accept": "application/json",
        },
      ).timeout(const Duration(seconds: 45)); // টাইমআউট বাড়িয়ে ৪৫ সেকেন্ড করা হলো

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['status'] == 'success') {
          return {
            'url': data['url']?.toString() ?? "",
            'title': data['title']?.toString() ?? "FB_Video_${DateTime.now().millisecondsSinceEpoch}",
            'thumbnail': data['thumbnail']?.toString() ?? "", 
            'source': data['source']?.toString() ?? "Facebook",
          };
        } else {
          throw data['message'] ?? "ভিডিওর তথ্য পাওয়া যায়নি।";
        }
      } else if (response.statusCode == 401) {
        throw "এপিআই কি (API Key) ভুল বা কাজ করছে না।";
      } else if (response.statusCode == 429) {
        throw "অতিরিক্ত রিকোয়েস্ট পাঠিয়েছেন। কিছুক্ষণ পর চেষ্টা করুন।";
      } else {
        final errorData = jsonDecode(response.body);
        throw errorData['detail'] ?? "সার্ভার এরর: ${response.statusCode}";
      }
    } catch (e) {
      // ইউজার ফ্রেন্ডলি এরর মেসেজ
      if (e.toString().contains("TimeoutException")) {
        throw "সার্ভার থেকে রেসপন্স পেতে দেরি হচ্ছে। আবার চেষ্টা করুন।";
      }
      throw "ফেসবুক ভিডিওটি পাওয়া যায়নি। লিঙ্কটি পাবলিক কি না নিশ্চিত করুন।";
    }
  }
}