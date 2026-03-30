import 'dart:convert';
import 'package:http/http.dart' as http;

class TikTokService {
  bool isTikTokLink(String url) {
    return url.contains("tiktok.com") || url.contains("vt.tiktok.com");
  }

  Future<Map<String, dynamic>> getVideoDetails(String url) async {
    try {
      const String pythonApiUrl = "https://linksyncro-api-1.onrender.com/get_media"; 
      
      final uri = Uri.parse("$pythonApiUrl?url=${Uri.encodeComponent(url)}");

      final response = await http.get(
        uri,
        headers: {
          "x-api-key": "demo_key_123", // আপনার পাইথন কোডে দেওয়া API Key
        },
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } else {
        throw "TikTok Server Error: ${response.statusCode}";
      }
    } catch (e) {
      print("TikTok Service Error: $e");
      rethrow; 
    }
  }
}