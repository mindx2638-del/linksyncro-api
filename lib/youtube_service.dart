import 'dart:convert';
import 'package:http/http.dart' as http;

class YouTubeService {
  static const String _apiUrl = "https://linksyncro-api.onrender.com/get_media";
  static const String _apiKey = "demo_key_123";

  // URL ভ্যালিডেশন লজিক (এটিAPI কল করার আগেই চেক করার জন্য দরকার)
  bool isYouTubeLink(String url) {
    if (url.isEmpty) return false;
    final String cleanUrl = url.trim().replaceAll(RegExp(r'[à¥¤â€”\s]+$'), '');
    final uri = Uri.tryParse(cleanUrl);
    if (uri == null) return false;
    return uri.host.contains('youtube.com') || uri.host.contains('youtu.be');
  }

  // ভিডিও ডিটেইলস ফেচ করা (শুধুমাত্র API ভিত্তিক)
  Future<Map<String, dynamic>> getVideoDetails(String url) async {
    try {
      final response = await http.get(
        Uri.parse("$_apiUrl?url=${Uri.encodeComponent(url.trim())}"),
        headers: {
          "x-api-key": _apiKey,
          "Accept": "application/json",
        },
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          return {
            'url': data['url'],
            'title': data['title'] ?? "YouTube_Video",
            'thumbnail': data['thumbnail'],
            'source': "YouTube",
          };
        } else {
          throw data['message'] ?? "Failed to fetch video details.";
        }
      } else {
        throw "Server Error: ${response.statusCode}";
      }
    } catch (e) {
      throw "Could not retrieve YouTube video: $e";
    }
  }
}