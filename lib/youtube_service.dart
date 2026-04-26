import 'dart:convert';
import 'package:http/http.dart' as http;

class YouTubeService {
  // API Configuration
  static const String _apiUrl = "https://linksyncro-api.onrender.com/get_media";
  static const String _apiKey = "demo_key_123";

  /// 1. Validate if the URL is a YouTube link
  bool isYouTubeLink(String url) {
    if (url.isEmpty) return false;
    final String cleanUrl = url.trim().toLowerCase();
    return cleanUrl.contains('youtube.com') || cleanUrl.contains('youtu.be');
  }

  /// 2. Get video details via your Python Backend API
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
        return jsonDecode(utf8.decode(response.bodyBytes));
      } else {
        // সার্ভারের এরর হ্যান্ডলিং
        throw "Server Error: ${response.statusCode}";
      }
    } catch (e) {
      print("YouTube Service Error: $e");
      rethrow;
    }
  }
}