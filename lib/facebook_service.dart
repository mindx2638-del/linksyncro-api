import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

class FacebookService {
  // আপনার Render API Endpoint
  static const String _apiUrl = "https://linksyncro-api-1.onrender.com/get_media";
  
  // API Key (আপনার Python main.py এর সাথে মিল থাকতে হবে)
  static const String _apiKey = "demo_key_123"; 

  // ফেসবুক লিঙ্ক চেনার লজিক
  bool isFacebookLink(String url) {
    String lowerUrl = url.toLowerCase();
    return lowerUrl.contains("facebook.com") || 
           lowerUrl.contains("fb.watch") || 
           lowerUrl.contains("fb.com");
  }

  Future<Map<String, String>> getVideoDetails(String url) async {
    try {
      // ১. লিঙ্ক পরিষ্কার করা
      String targetUrl = url.trim();

      // ২. এপিআই কল করা (হেডারে এপিআই কি সহ)
      final response = await http.get(
        Uri.parse("$_apiUrl?url=${Uri.encodeComponent(targetUrl)}"),
        headers: {
          "x-api-key": _apiKey,
          "Accept": "application/json",
        },
      ).timeout(const Duration(seconds: 50)); // Render এর জন্য একটু বেশি সময় দেওয়া হয়েছে

      // ৩. রেসপন্স চেক করা
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        
        // পাইথন সার্ভার থেকে 'status': 'success' আসলে
        if (data['status'] == 'success' || data['url'] != null) {
          return {
            'url': data['url']?.toString() ?? "",
            'title': data['title']?.toString() ?? "FB_Video_${DateTime.now().millisecondsSinceEpoch}",
            'thumbnail': data['thumbnail']?.toString() ?? "", 
            'source': data['source']?.toString() ?? "Facebook",
          };
        } else {
          throw data['detail'] ?? "Video not found on server.";
        }
      } else if (response.statusCode == 401) {
        throw "Unauthorized: API Key mismatch.";
      } else if (response.statusCode == 404) {
        throw "Video not found. Cookies might be expired.";
      } else if (response.statusCode == 429) {
        throw "Too many requests. Please wait a minute.";
      } else {
        // অন্য যেকোনো সার্ভার এরর সরাসরি দেখানো
        final errorData = jsonDecode(utf8.decode(response.bodyBytes));
        throw errorData['detail'] ?? "Server returned error: ${response.statusCode}";
      }
    } catch (e) {
      // আসল এরর মেসেজটি থ্রো করা যেন ইউজার দেখতে পায়
      if (e is TimeoutException) {
        throw "Server is taking too long (Render Cold Start). Try again.";
      }
      
      // এখানে আমি মেসেজটি পরিবর্তন করেছি যাতে আপনি আসল এরর দেখতে পান
      throw e.toString().replaceFirst("Exception: ", "");
    }
  }
}