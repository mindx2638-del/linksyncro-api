import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

class FacebookService {
  static const String _apiUrl = "https://linksyncro-api-1.onrender.com/get_media";
  static const String _apiKey = "demo_key_123"; 

  bool isFacebookLink(String url) {
    String lowerUrl = url.toLowerCase();
    return lowerUrl.contains("facebook.com") || 
           lowerUrl.contains("fb.watch") || 
           lowerUrl.contains("fb.com");
  }

  Future<Map<String, String>> getVideoDetails(String url) async {
    try {
      String targetUrl = url.trim();

      final response = await http.get(
        Uri.parse("$_apiUrl?url=${Uri.encodeComponent(targetUrl)}"),
        headers: {
          "x-api-key": _apiKey,
          "Accept": "application/json",
        },
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        
        // আপনার পাইথন সার্ভার থেকে ডাটা আসলে তা রিটার্ন করবে
        return {
          'url': data['url']?.toString() ?? "",
          'title': data['title']?.toString() ?? "FB_Video_${DateTime.now().millisecondsSinceEpoch}",
          'thumbnail': data['thumbnail']?.toString() ?? "", 
          'source': data['source']?.toString() ?? "Facebook",
        };
      } else {
        // সার্ভার থেকে আসা সঠিক এরর মেসেজটি ধরবে
        final errorData = jsonDecode(utf8.decode(response.bodyBytes));
        throw errorData['detail'] ?? "Server Error: ${response.statusCode}";
      }
    } catch (e) {
      if (e is TimeoutException) {
        throw "সার্ভার রেসপন্স দিচ্ছে না। রেন্ডার সার্ভারটি ব্রাউজারে একবার ওপেন করুন।";
      }
      
      // গুরুত্বপূর্ণ: এই লাইনটি আপনাকে স্ক্রিনে আসল এররটি দেখাবে
      // যেমন: '403 Forbidden' বা 'Sign in to confirm you are not a bot'
      throw e.toString().replaceFirst("Exception: ", "");
    }
  }
}