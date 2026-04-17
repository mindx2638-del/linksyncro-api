import 'dart:convert';
import 'package:http/http.dart' as http;

class InstagramService {
  // আপনার নতুন ডকার এপিআই লিঙ্ক
  final String myApiUrl = "https://linksyncro-api-2.onrender.com/extract?url=";

  // ১. লিঙ্কটি ইনস্টাগ্রামের কি না তা চেক করা
  bool isInstagramLink(String url) {
    if (url.isEmpty) return false;
    return url.contains("instagram.com") || url.contains("instagr.am");
  }

  // ২. আপনার নতুন Render Docker Server থেকে ডাটা আনা
  Future<Map<String, dynamic>> getVideoDetails(String url) async {
    try {
      // ইউটিউব সার্ভিসের মতো একই ফরম্যাটে রিকোয়েস্ট পাঠানো
      final uri = Uri.parse("$myApiUrl${Uri.encodeComponent(url.trim())}");

      final response = await http.get(
        uri,
        headers: {
          "x-api-key": "demo_key_123", // আপনার পাইথন কোডে API Key থাকলে এটি থাকবে
        },
      ).timeout(const Duration(seconds: 60)); // ইনস্টাগ্রাম প্রসেসিং এর জন্য ৬০ সেকেন্ড সময় দেওয়া হয়েছে

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (data['status'] == 'success') {
          return {
            'title': data['title'] ?? "Instagram_Video_${DateTime.now().millisecondsSinceEpoch}",
            'url': data['url'], // সার্ভার থেকে আসা ডিরেক্ট ভিডিও লিঙ্ক
            'thumbnail': data['thumbnail'] ?? "",
            'author': "Instagram",
          };
        } else {
          throw data['message'] ?? "Could not extract Instagram media.";
        }
      } else {
        throw "Server Error: ${response.statusCode}";
      }
    } catch (e) {
      print("Instagram Service Error: $e");
      // ইউজারকে দেখানোর জন্য সহজ ভাষায় এরর পাঠানো
      throw "Instagram Error: ${e.toString().replaceAll("Exception:", "")}";
    }
  }
}