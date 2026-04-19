import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

class FacebookService {
  // API Endpoint
  static const String _apiUrl = "https://linksyncro-api-1.onrender.com/get_media";
  
  // API Key
  static const String _apiKey = "demo_key_123"; 

  // Logic to identify various Facebook URL formats
  bool isFacebookLink(String url) {
    String lowerUrl = url.toLowerCase();
    return lowerUrl.contains("facebook.com") || 
           lowerUrl.contains("fb.watch") || 
           lowerUrl.contains("fb.com");
  }

  // রিটার্ন টাইপ dynamic করা হয়েছে যাতে List (formats) হ্যান্ডেল করা যায়
  Future<Map<String, dynamic>> getVideoDetails(String url) async {
    try {
      // 1. URL Cleaning
      String targetUrl = url.trim();

      // 2. API Call
      final response = await http.get(
        Uri.parse("$_apiUrl?url=${Uri.encodeComponent(targetUrl)}"),
        headers: {
          "x-api-key": _apiKey,
          "Accept": "application/json",
        },
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['status'] == 'success') {
          // ফরম্যাট লিস্ট রিটার্ন করা হচ্ছে
          return {
            'formats': data['formats'] ?? [], 
            'title': data['title']?.toString() ?? "FB_Video_${DateTime.now().millisecondsSinceEpoch}",
            'thumbnail': data['thumbnail']?.toString() ?? "", 
            'source': data['source']?.toString() ?? "Facebook",
          };
        } else {
          throw data['message'] ?? "Video details not found.";
        }
      } else if (response.statusCode == 401) {
        throw "Invalid or unauthorized API Key.";
      } else if (response.statusCode == 429) {
        throw "Too many requests. Please try again later.";
      } else {
        final errorData = jsonDecode(response.body);
        throw errorData['detail'] ?? "Server Error: ${response.statusCode}";
      }
    } catch (e) {
      if (e is TimeoutException) {
        throw "Connection timed out. Please try again.";
      }
      throw "Could not retrieve Facebook video. Please ensure the link is public.";
    }
  }
}