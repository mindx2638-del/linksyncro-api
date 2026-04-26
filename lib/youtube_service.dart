import 'dart:convert';
import 'package:http/http.dart' as http;

class YouTubeService {
  // আপনার API Endpoint এবং Key
  static const String _apiUrl = "https://linksyncro-api.onrender.com/get_media";
  static const String _apiKey = "demo_key_123";

  /// 1. Validate if the URL is a YouTube link
  bool isYouTubeLink(String url) {
    if (url.isEmpty) return false;
    final String cleanUrl = url.trim().replaceAll(RegExp(r'[à¥¤â€”\s]+$'), '');
    final uri = Uri.tryParse(cleanUrl);
    if (uri == null) return false;
    return uri.host.contains('youtube.com') || uri.host.contains('youtu.be');
  }

  /// 2. API এর মাধ্যমে ভিডিও ডিটেইলস নিয়ে আসা
  Future<Map<String, dynamic>> getVideoDetails(String url) async {
    try {
      // API তে রিকোয়েস্ট পাঠানো
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _apiKey, // আপনার API Key হেডার হিসেবে পাঠানো
        },
        body: jsonEncode({'url': url}),
      );

      if (response.statusCode == 200) {
        // API থেকে পাওয়া JSON ডেটা ডিকোড করা
        final Map<String, dynamic> data = jsonDecode(response.body);
        return data; 
      } else {
        throw "Server Error: ${response.statusCode}";
      }
    } catch (e) {
      throw "Error: ${e.toString()}";
    }
  }

  /// 3. ফাইল নেম ক্লিনিং (API থেকে আসার পর প্রয়োজন হলে)
  String safeFileName(String input) {
    return input.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
  }
}