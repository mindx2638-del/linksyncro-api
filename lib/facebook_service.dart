import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

class FacebookService {
  // আপনার নতুন ডকার এপিআই লিঙ্ক (api-2)
  // এন্ডপয়েন্ট '/extract' ব্যবহার করা হয়েছে যা আপনার নতুন সার্ভারের সাথে সামঞ্জস্যপূর্ণ
  static const String _apiUrl = "https://linksyncro-api-2.onrender.com/extract";
  
  static const String _apiKey = "demo_key_123"; 

  bool isFacebookLink(String url) {
    if (url.isEmpty) return false;
    String lowerUrl = url.toLowerCase();
    return lowerUrl.contains("facebook.com") || 
           lowerUrl.contains("fb.watch") || 
           lowerUrl.contains("fb.com");
  }

  Future<Map<String, String>> getVideoDetails(String url) async {
    try {
      String targetUrl = url.trim();

      // এপিআই কল
      final response = await http.get(
        Uri.parse("$_apiUrl?url=${Uri.encodeComponent(targetUrl)}"),
        headers: {
          "x-api-key": _apiKey,
          "Accept": "application/json",
        },
      ).timeout(const Duration(seconds: 60)); // ফেসবুক প্রসেসিং এর জন্য ৬০ সেকেন্ড সময়

      if (response.statusCode == 200) {
        // UTF-8 ডিকোডিং নিশ্চিত করা হয়েছে যাতে বাংলা টাইটেল ঠিক থাকে
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (data['status'] == 'success') {
          return {
            'url': data['url']?.toString() ?? "",
            'title': data['title']?.toString() ?? "FB_Video_${DateTime.now().millisecondsSinceEpoch}",
            'thumbnail': data['thumbnail']?.toString() ?? "", 
            'source': "Facebook",
          };
        } else {
          throw data['message'] ?? "Video details not found.";
        }
      } else if (response.statusCode == 401) {
        throw "Invalid or unauthorized API Key.";
      } else {
        throw "Server Error: ${response.statusCode}";
      }
    } catch (e) {
      if (e is TimeoutException) {
        throw "Connection timed out. Please try again.";
      }
      // ইউজারকে মূল এরর মেসেজটি দেখানো
      throw e.toString().contains("Error") ? e.toString() : "Could not retrieve Facebook video. Ensure it's public.";
    }
  }
}