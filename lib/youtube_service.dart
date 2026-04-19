import 'dart:convert';
import 'package:http/http.dart' as http;

class YouTubeService {
  // আপনার রেন্ডার সার্ভারের ইউআরএল
  final String _apiUrl = "https://linksyncro-api-1.onrender.com/get_media";
  
  // আপনার সার্ভারে যে API Key সেট করেছেন
  final String _apiKey = "demo_key_123"; 

  Future<Map<String, dynamic>> getVideoDetails(String url) async {
    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          "Content-Type": "application/json",
          "x-api-key": _apiKey,
        },
        body: jsonEncode({"url": url}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // সার্ভার থেকে আসা ডাটাকে আপনার অ্যাপের ফরম্যাটে সাজান
        return {
          'title': data['title'] ?? 'Video',
          'url': _extractBestUrl(data['formats']), // ফরম্যাট থেকে সেরা ইউআরএল বের করুন
          'thumbnail': data['thumbnail'] ?? '',
          'author': data['source'] ?? 'Unknown',
        };
      } else {
        throw "সার্ভার এরর: ${response.statusCode}";
      }
    } catch (e) {
      throw "কানেকশন এরর: $e";
    }
  }

  // সার্ভার থেকে আসা ফরম্যাট লিস্ট থেকে সেরা ইউআরএল খুঁজে বের করা
  String _extractBestUrl(dynamic formats) {
    if (formats != null && formats is List && formats.isNotEmpty) {
      // তালিকার প্রথমটিই সাধারণত সেরা রেজোলিউশন হয় কারণ আমরা সার্ভারে সর্ট করে রেখেছি
      return formats[0]['url'];
    }
    return "";
  }
}