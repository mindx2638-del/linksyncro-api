import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

class FacebookService {
  final List<String> _apiBaseUrls = [
    "https://linksyncro-api-f1k4.onrender.com", 
    "https://linksyncro-api-1.onrender.com",           // Render (Backup)
  ];

  static const String _apiKey = "demo_key_123"; 

  bool isFacebookLink(String url) {
    String lowerUrl = url.toLowerCase();
    return lowerUrl.contains("facebook.com") || 
           lowerUrl.contains("fb.watch") || 
           lowerUrl.contains("fb.com");
  }

  Future<Map<String, String>> getVideoDetails(String url) async {
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
        ).timeout(const Duration(seconds: 35));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          
          if (data['status'] == 'success') {
            return {
              'url': data['url']?.toString() ?? "",
              'title': data['title']?.toString() ?? "FB_Video_${DateTime.now().millisecondsSinceEpoch}",
              'thumbnail': data['thumbnail']?.toString() ?? "", 
              'source': data['source']?.toString() ?? "Facebook",
            };
          } else {
            lastErrorMessage = data['message'];
            continue; 
          }
        } else if (response.statusCode == 401) {
          throw "Invalid or unauthorized API Key."; 
        } else if (response.statusCode == 429) {
          lastErrorMessage = "Server rate limit exceeded.";
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
    throw lastErrorMessage ?? "Unable to connect to servers. Please ensure the link is public.";
  }
}
