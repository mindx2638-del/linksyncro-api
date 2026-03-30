import 'dart:convert';
import 'package:http/http.dart' as http;

class FacebookService {
  // আপনার Render API এর মূল লিঙ্ক
  static const String _apiUrl = "https://linksyncro-api-1.onrender.com/get_video";
  
  // ব্যাকএন্ডে যে কী (Key) সেট করেছেন সেটি এখানে দিতে হবে
  static const String _apiKey = "demo_key_123"; 

  bool isFacebookLink(String url) {
    return url.contains("facebook.com") || 
           url.contains("fb.watch") || 
           url.contains("fb.com") ||
           url.contains("web.facebook.com"); // এটিও যোগ করা ভালো
  }

  Future<Map<String, String>> getVideoDetails(String url) async {
    try {
      // URL এনকোড করা হচ্ছে যাতে স্পেশাল ক্যারেক্টার সমস্যা না করে
      final uri = Uri.parse("$_apiUrl?url=${Uri.encodeComponent(url.trim())}");

      final response = await http.get(
        uri,
        headers: {
          "x-api-key": _apiKey, // ❗ এই হেডারটি অবশ্যই দিতে হবে
          "Accept": "application/json",
        },
      ).timeout(const Duration(seconds: 45)); // Render-এর জন্য সময় ১০ সেকেন্ড বাড়ানো হয়েছে

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // আপনার ব্যাকএন্ডের রেসপন্স ফরম্যাট অনুযায়ী লজিক
        if (data['url'] != null) {
          return {
            'url': data['url'].toString(),
            'title': data['title']?.toString() ?? "FB_Video_${DateTime.now().millisecondsSinceEpoch}",
            'thumbnail': data['thumbnail']?.toString() ?? "", 
          };
        } else {
          throw "Video link not found in response";
        }
      } else if (response.statusCode == 401) {
        throw "API Key mismatch or invalid";
      } else if (response.statusCode == 429) {
        throw "Too many requests. Please wait a minute.";
      } else {
        throw "Server error: ${response.statusCode}";
      }
    } catch (e) {
      // ইউজারকে সহজ ভাষায় এরর দেখানো
      throw "Error: $e";
    }
  }
}