import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

class InstagramService {
 
  final List<String> _apiBaseUrls = [
    "https://linksyncro-api-b08a.onrender.com",             // Render (Backup)
  ];

  static const String _apiKey = "demo_key_123"; 
  bool isInstagramLink(String url) {
    String lowerUrl = url.toLowerCase();
    return lowerUrl.contains("instagram.com");
  }
  Future<Map<String, dynamic>> getVideoDetails(String url) async {
    String targetUrl = url.trim();
    String? lastErrorMessage;
    for (String baseUrl in _apiBaseUrls) {
      try {
        final uri = Uri.parse("$baseUrl/get_media?url=${Uri.encodeComponent(targetUrl)}");
        final response = await http.get(
          uri,
          headers: {
            "x-api-key": _apiKey,
            "Accept": "application/json",
          },
        ).timeout(const Duration(seconds: 40)); 
        if (response.statusCode == 200) {
          return jsonDecode(utf8.decode(response.bodyBytes));
        } else if (response.statusCode == 429) {
          lastErrorMessage = "Server rate limit exceeded. Please try again later.";
          continue; 
        } else {
          lastErrorMessage = "Server Error: ${response.statusCode}";
          continue;
        }
      } catch (e) {
        if (e is TimeoutException) {
          lastErrorMessage = "Server request timed out.";
        } else {
          lastErrorMessage = e.toString();
        }
        continue; 
      }
    }
    throw lastErrorMessage ?? "Unable to retrieve Instagram video details.";
  }
}