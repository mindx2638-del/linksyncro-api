import 'dart:convert';
import 'package:http/http.dart' as http;

class YouTubeService {
  // আপনার পাইথন ব্যাকএন্ডের ইউআরএল
  static const String _apiUrl = "https://linksyncro-api.onrender.com/get_media";
  
  // API Key
  static const String _apiKey = "demo_key_123";

  /// 1. Validate if the URL is a YouTube link
  bool isYouTubeLink(String url) {
    if (url.isEmpty) return false;
    // বাংলা যতিচিহ্ন বা স্পেস ক্লিন করা
    final String cleanUrl = url.trim().replaceAll(RegExp(r'[।—\s]+$'), '');
    final uri = Uri.tryParse(cleanUrl);
    if (uri == null) return false;
    return uri.host.contains('youtube.com') || uri.host.contains('youtu.be');
  }

  /// 2. Get video details and download URL from Python Backend
  Future<Map<String, dynamic>> getVideoDetails(String url) async {
    try {
      // URL Validate করা
      if (!isYouTubeLink(url)) {
        throw "Invalid YouTube URL.";
      }

      // API Call
      final response = await http.get(
        Uri.parse("$_apiUrl?url=${Uri.encodeComponent(url)}"),
        headers: {
          "x-api-key": _apiKey,
          "Accept": "application/json",
        },
      ).timeout(const Duration(seconds: 45));

      // Handling Response
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        
        // ফাইলনেম ক্লিন করে ডেটা রিটার্ন করা
        data['title'] = _safeFileName(data['title'] ?? "Video");
        return data;
        
      } else if (response.statusCode == 404) {
        throw "Video is unavailable (Private, Removed, or Live).";
      } else if (response.statusCode == 401) {
        throw "Unauthorized: Invalid API Key.";
      } else {
        throw "Server Error: ${response.statusCode}";
      }
    } catch (e) {
      // আগের মতোই এরর হ্যান্ডলিং বজায় রাখা
      throw e.toString().replaceAll("Exception:", "").trim();
    }
  }

  /// 3. Clean filename to avoid FileSystemException
  String _safeFileName(String input) {
    return input.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
  }

  // রিসোর্স ক্লোজ করার দরকার নেই, কারণ এখন সব API হ্যান্ডেল করছে
  void close() {}
}