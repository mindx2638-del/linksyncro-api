import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

class FacebookService {
  // API Endpoint (Ensure this matches your FastAPI '/get_media' route)
  static const String _apiUrl = "https://linksyncro-api.onrender.com/get_media";
  
  // API Key (Must match the key defined in your FastAPI backend)
  static const String _apiKey = "demo_key_123"; 

  // Logic to identify various Facebook URL formats (Regular, Watch, FB.com)
  bool isFacebookLink(String url) {
    String lowerUrl = url.toLowerCase();
    return lowerUrl.contains("facebook.com") || 
           lowerUrl.contains("fb.watch") || 
           lowerUrl.contains("fb.com");
  }

  Future<Map<String, String>> getVideoDetails(String url) async {
    try {
      // 1. URL Cleaning: Trim whitespace to ensure valid encoding
      String targetUrl = url.trim();

      // 2. API Call with API Key in Headers
      final response = await http.get(
        Uri.parse("$_apiUrl?url=${Uri.encodeComponent(targetUrl)}"),
        headers: {
          "x-api-key": _apiKey,
          "Accept": "application/json",
        },
      ).timeout(const Duration(seconds: 45)); // Increased timeout for server processing

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
          throw data['message'] ?? "Video details not found.";
        }
      } else if (response.statusCode == 401) {
        throw "Invalid or unauthorized API Key.";
      } else if (response.statusCode == 429) {
        throw "Too many requests. Please try again later.";
      } else {
        final errorData = jsonDecode(response.body);
        throw errorData['detail'] ?? "Server Error: ${response.statusCode}";
      }
    } catch (e) {
      // User-friendly error handling
      if (e is TimeoutException) {
        throw "Connection timed out. Please try again.";
      }
      
      // Generic error fallback
      throw "Could not retrieve Facebook video. Please ensure the link is public.";
    }
  }
}