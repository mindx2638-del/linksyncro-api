import 'dart:convert';
import 'package:http/http.dart' as http;

class InstagramService {
  static const String _apiUrl = "https://linksyncro-api-1.onrender.com/get_video";

  // লিঙ্কটি ইন্সটাগ্রামের কি না তা চেক করার লজিক
  bool isInstagramLink(String url) {
    return url.contains("instagram.com") || url.contains("instagr.am");
  }

  // ইন্সটাগ্রাম ভিডিওর ডিটেইলস নিয়ে আসা
  Future<Map<String, String>> getVideoDetails(String url) async {
    try {
      final response = await http.get(Uri.parse("$_apiUrl?url=$url"));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // এপিআই থেকে ইউআরএল এবং টাইটেল রিটার্ন করা
        return {
          'url': data['url'] as String,
          'title': data['title'] ?? "Insta_Video_${DateTime.now().millisecondsSinceEpoch}",
        };
      } else {
        throw "Server busy or invalid Instagram link";
      }
    } catch (e) {
      throw "Failed to fetch Instagram video: $e";
    }
  }
}