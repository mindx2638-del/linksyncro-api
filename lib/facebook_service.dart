import 'dart:convert';
import 'package:http/http.dart' as http;

class FacebookService {
  static const String _apiUrl = "https://linksyncro-api-1.onrender.com/get_video";

  // সব ধরনের ফেসবুক লিঙ্ক শনাক্ত করার উন্নত লজিক
  bool isFacebookLink(String url) {
    return url.contains("facebook.com") || 
           url.contains("fb.watch") || 
           url.contains("fb.com");
  }

  Future<Map<String, String>> getVideoDetails(String url) async {
    try {
      // লিঙ্ক থেকে ট্র্যাকিং আইডি বাদ দিয়ে ক্লিন করা (সাউন্ড ও ডাটা পেতে সুবিধা হয়)
      String cleanUrl = url;
      if (url.contains("?")) {
        cleanUrl = url.split("?").first;
      }

      final response = await http.get(
        Uri.parse("$_apiUrl?url=${Uri.encodeComponent(cleanUrl)}"),
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['status'] == 'success') {
          return {
            'url': data['url']?.toString() ?? "",
            'title': data['title']?.toString() ?? "FB_Video_${DateTime.now().millisecondsSinceEpoch}",
            'thumbnail': data['thumbnail']?.toString() ?? "", 
          };
        } else {
          throw data['message'] ?? "Video analysis failed";
        }
      } else {
        throw "Server error: ${response.statusCode}";
      }
    } catch (e) {
      throw "এই ভিডিওটি পাবলিক নয় অথবা লিঙ্কটি ভুল: $e";
    }
  }
}