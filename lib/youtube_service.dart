import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

class YouTubeService {
  static const String _apiUrl = "https://linksyncro-api-1.onrender.com/get_media";
  static const String _apiKey = "demo_key_123";

  /// 1. Validate if the URL is a YouTube link (Using your original logic)
  bool isYouTubeLink(String url) {
    if (url.isEmpty) return false;
    final String cleanUrl = url.trim().replaceAll(RegExp(r'[।—\s]+$'), '');
    final uri = Uri.tryParse(cleanUrl);
    if (uri == null) return false;
    
    // আপনার লজিক অনুযায়ী ডোমেইন চেক
    return uri.host.contains('youtube.com') || 
           uri.host.contains('youtu.be') ||
           uri.host.contains('http://googleusercontent.com/youtube.com/');
  }

  /// 2. Get video details and formats from Backend API
  Future<Map<String, dynamic>> getVideoDetails(String url) async {
    try {
      final String cleanUrl = url.trim().replaceAll(RegExp(r'[।—\s]+$'), '');
      
      // API কল করা হচ্ছে
      final response = await http.get(
        Uri.parse("$_apiUrl?url=${Uri.encodeComponent(cleanUrl)}"),
        headers: {
          "x-api-key": _apiKey,
          "Accept": "application/json",
        },
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (data['status'] == 'success') {
          // আপনার অ্যাপের কোয়ালিটি সিলেকশন ফিচারের জন্য 'formats' লিস্ট পাঠানো হচ্ছে
          return {
            'formats': data['formats'] ?? [],
            'title': _safeFileName(data['title'] ?? "YouTube_Video"),
            'thumbnail': data['thumbnail']?.toString() ?? "",
            'source': "YouTube",
          };
        } else {
          throw data['message'] ?? "Could not extract YouTube video.";
        }
      } else if (response.statusCode == 429) {
        throw "Rate limit exceeded. Please wait a moment.";
      } else {
        throw "Server Error: ${response.statusCode}";
      }
    } catch (e) {
      if (e is TimeoutException) {
        throw "Connection timed out. Please check your internet.";
      }
      throw "YouTube download failed. ${e.toString().replaceAll("Exception:", "")}";
    }
  }

  /// 3. Clean filename to avoid FileSystemException (Error 36)
  String _safeFileName(String input) {
    return input.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
  }
}