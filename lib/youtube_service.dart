import 'dart:convert';
import 'package:http/http.dart' as http;

class YouTubeService {
  // আপনার FastAPI এন্ডপয়েন্ট (অন্যান্য সার্ভিসের মতো একই)
  static const String _apiUrl = "https://linksyncro-api.onrender.com/get_media";
  static const String _apiKey = "demo_key_123";

  // ইউটিউব লিংক কিনা চেক করার লজিক
  bool isYouTubeLink(String url) {
    String lowerUrl = url.toLowerCase();
    return lowerUrl.contains("youtube.com") || lowerUrl.contains("youtu.be");
  }

  // সার্ভার থেকে ডাটা আনার ফাংশন
  Future<Map<String, dynamic>> getVideoDetails(String url) async {
    try {
      final uri = Uri.parse("$_apiUrl?url=${Uri.encodeComponent(url)}");
      final response = await http.get(
        uri,
        headers: {
          "x-api-key": _apiKey,
          "Accept": "application/json",
        },
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } else {
        throw "Server Error: ${response.statusCode}";
      }
    } catch (e) {
      print("YouTube Service Error: $e");
      rethrow;
    }
  }
}