import 'dart:convert';
import 'package:http/http.dart' as http;

class FacebookService {
  static const String _apiUrl = "https://linksyncro-api-1.onrender.com/get_video";

  // ইউআরএলটি ফেসবুকের কি না তা চেক করার লজিক
  bool isFacebookLink(String url) {
    return url.contains("facebook.com") || 
           url.contains("fb.watch") || 
           url.contains("fb.com");
  }

  // ফেসবুক ভিডিওর ডিটেইলস, থাম্বনেইল এবং ডাউনলোড লিঙ্ক নিয়ে আসা
  Future<Map<String, String>> getVideoDetails(String url) async {
    try {
      final response = await http.get(Uri.parse("$_apiUrl?url=${Uri.encodeComponent(url)}"))
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        return {
          'url': data['url']?.toString() ?? "",
          'title': data['title']?.toString() ?? "FB_Video_${DateTime.now().millisecondsSinceEpoch}",
          // API থেকে থাম্বনেইল ডাটা নেওয়া হচ্ছে
          'thumbnail': data['thumbnail']?.toString() ?? "", 
        };
      } else {
        throw "Server busy or invalid Facebook link";
      }
    } catch (e) {
      throw "Failed to fetch Facebook video: $e";
    }
  }
}