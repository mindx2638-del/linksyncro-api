import 'dart:convert';
import 'package:http/http.dart' as http;

class TwitterService {
  static const String _apiUrl = "https://linksyncro-api-1.onrender.com/get_media";
  static const String _apiKey = "demo_key_123";

  bool isTwitterLink(String url) {
    return url.contains("twitter.com") || url.contains("x.com");
  }

  Future<Map<String, dynamic>> getVideoDetails(String url) async {
    final uri = Uri.parse("$_apiUrl?url=${Uri.encodeComponent(url)}");

    final response = await http.get(
      uri,
      headers: {"x-api-key": _apiKey},
    ).timeout(const Duration(seconds: 45));

    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw "Twitter fetch failed";
    }
  }
}