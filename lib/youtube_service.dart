import 'dart:convert';
import 'package:http/http.dart' as http;

class YouTubeService {
  static const String _apiUrl = "https://linksyncro-api-1.onrender.com/get_media";
  static const String _apiKey = "demo_key_123";

  // শুধু লিঙ্ক চেক করবে
  bool isYouTubeLink(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.host.contains('youtube.com') || uri.host.contains('youtu.be');
  }

  // পাইথন ব্যাকএন্ড থেকে ভিডিও ডিটেইলস আনবে
  Future<Map<String, dynamic>> getVideoDetails(String url) async {
    final response = await http.get(
      Uri.parse("$_apiUrl?url=${Uri.encodeComponent(url)}"),
      headers: {"x-api-key": _apiKey},
    );

    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw "সার্ভার এরর: ${response.statusCode}";
    }
  }
}