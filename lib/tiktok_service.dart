import 'dart:convert';
import 'package:http/http.dart' as http;

class TikTokService {
  // আপনার পাইথন এপিআই-এর ইউআরএল (Render/Heroku থেকে পাওয়া লিঙ্কটি এখানে বসান)
  final String _baseUrl = "https://your-python-api.onrender.com/get_media";
  
  // আপনার পাইথন কোডে যে API Key দিয়েছেন (demo_key_123) সেটি এখানে দিন
  final String _apiKey = "demo_key_123";

  /// চেক করবে লিঙ্কটি টিকটকের কি না (vt.tiktok, vm.tiktok বা সাধারণ লিঙ্ক সব কাভার করবে)
  bool isTikTokLink(String url) {
    final lowerUrl = url.toLowerCase();
    return lowerUrl.contains("tiktok.com");
  }

  /// টিকটক ভিডিওর ডিটেইলস নিয়ে আসার মূল ফাংশন
  Future<Map<String, dynamic>> getVideoDetails(String url) async {
    try {
      // ইউআরএলটি এনকোড করে এপিআই কল করা হচ্ছে
      final uri = Uri.parse("$_baseUrl?url=${Uri.encodeComponent(url)}");

      final response = await http.get(
        uri,
        headers: {
          "x-api-key": _apiKey, // এপিআই কী হেডারে পাঠানো হচ্ছে
          "Accept": "application/json",
        },
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        // রেসপন্স ডিকোড করা (বাংলা ফন্ট সাপোর্ট করার জন্য utf8.decode ব্যবহার করা হয়েছে)
        final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (data['status'] == 'success') {
          return {
            "status": "success",
            "url": data['url'], // ভিডিওর সরাসরি ডাউনলোড লিঙ্ক
            "title": data['title'] ?? "TikTok_Video_${DateTime.now().millisecondsSinceEpoch}",
            "thumbnail": data['thumbnail'],
            "duration": data['duration'],
            "source": "TikTok",
          };
        } else {
          throw "Could not find video data on server";
        }
      } else if (response.statusCode == 401) {
        throw "API Key Unauthorized! Please check your settings.";
      } else if (response.statusCode == 429) {
        throw "Too many requests. Please try again after 1 minute.";
      } else {
        throw "Server Error: ${response.statusCode}";
      }
    } catch (e) {
      // যেকোনো নেটওয়ার্ক বা কোডিং এরর হ্যান্ডেল করবে
      throw "TikTok Downloader Error: $e";
    }
  }
}