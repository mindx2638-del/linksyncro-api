import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

class FacebookService {
  // ১. আপনার সব নতুন রেন্ডার/রেলওয়ে লিঙ্ক এখানে যোগ করুন
  final List<String> _apiBaseUrls = [
    "https://linksyncro-api-8itj.onrender.com",
    "https://linksyncro-api.onrender.com",       // Render Acc 1
  ];

  static const String _apiKey = "demo_key_123"; 

  bool isFacebookLink(String url) {
    String lowerUrl = url.toLowerCase();
    return lowerUrl.contains("facebook.com") || 
           lowerUrl.contains("fb.watch") || 
           lowerUrl.contains("fb.com") ||
           lowerUrl.contains("web.facebook.com"); // বাড়তি নিরাপত্তার জন্য যোগ করা হয়েছে
  }

  Future<Map<String, String>> getVideoDetails(String url) async {
    String targetUrl = url.trim();
    String? lastErrorMessage;

    // ২. এই লুপটি আপনার দেওয়া সব সার্ভারে একে একে চেষ্টা করবে
    for (String baseUrl in _apiBaseUrls) {
      try {
        // এখানে আপনার ব্যাকএন্ড অনুযায়ী '/get_media' ব্যবহার করা হয়েছে
        final uri = Uri.parse("$baseUrl/get_media?url=${Uri.encodeComponent(targetUrl)}");
        
        final response = await http.get(
          uri,
          headers: {
            "x-api-key": _apiKey,
            "Accept": "application/json",
          },
        ).timeout(const Duration(seconds: 35));

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
            lastErrorMessage = data['message'];
            continue; // পরের সার্ভারে ট্রাই করবে
          }
        } else if (response.statusCode == 401) {
          throw "Invalid or unauthorized API Key."; 
        } else if (response.statusCode == 429) {
          lastErrorMessage = "Server rate limit exceeded.";
          continue; 
        }
      } catch (e) {
        if (e is TimeoutException) {
          lastErrorMessage = "Server request timed out.";
        } else {
          lastErrorMessage = e.toString();
        }
        continue; // কোনো এরর হলে পরের লিঙ্কে যাবে
      }
    }
    throw lastErrorMessage ?? "Unable to connect to servers. Please ensure the link is public.";
  }
}