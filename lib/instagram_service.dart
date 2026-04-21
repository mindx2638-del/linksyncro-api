import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

class InstagramService {
  static const String _apiUrl = "https://linksyncro-api-1.onrender.com/get_media";
  static const String _apiKey = "demo_key_123"; 

  // ১. লিঙ্কটি ইনস্টাগ্রামের কি না তা চেক করা
  bool isInstagramLink(String url) {
    String lowerUrl = url.toLowerCase();
    return lowerUrl.contains("instagram.com");
  }

  // ২. পাইথন সার্ভার থেকে ডাটা আনা
  Future<Map<String, dynamic>> getVideoDetails(String url) async {
    try {
      final uri = Uri.parse("$_apiUrl?url=${Uri.encodeComponent(url.trim())}");

      final response = await http.get(
        uri,
        headers: {
          "x-api-key": _apiKey,
          "Accept": "application/json",
        },
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (data['status'] == 'success') {
          // অন্যান্য সার্ভিসের সাথে মিল রেখে এখানেও একই ফরম্যাটে ডাটা রিটার্ন করছি
          return {
            'formats': data['formats'] ?? [],
            'title': data['title']?.toString() ?? "IG_Video_${DateTime.now().millisecondsSinceEpoch}",
            'thumbnail': data['thumbnail']?.toString() ?? "", 
            'source': data['source']?.toString() ?? "Instagram",
          };
        } else {
          throw data['message'] ?? "Could not extract Instagram video.";
        }
      } else {
        throw "Server Error: ${response.statusCode}";
      }
    } catch (e) {
      if (e is TimeoutException) {
        throw "Connection timed out. Please check your internet.";
      }
      throw "Instagram download failed. Link might be private or invalid.";
    }
  }
}
