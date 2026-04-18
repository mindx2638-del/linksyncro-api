import 'dart:convert';
import 'package:http/http.dart' as http;

class InstagramService {
  // ১. লিঙ্কটি ইনস্টাগ্রামের কি না তা চেক করা
  bool isInstagramLink(String url) {
    return url.contains("instagram.com");
  }

  // ২. আপনার Render Python Server থেকে ডাটা আনা
  Future<Map<String, dynamic>> getVideoDetails(String url) async {
    try {
      // পরিবর্তন: URL এর শেষে /get_media যোগ করা হয়েছে
      const String pythonApiUrl = "https://linksyncro-api-2.onrender.com/get_media"; 
      
      final uri = Uri.parse("$pythonApiUrl?url=${Uri.encodeComponent(url)}");

      final response = await http.get(
        uri,
        headers: {
          "x-api-key": "demo_key_123", // পাইথন কোডের API Key এর সাথে মিল থাকতে হবে
        },
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } else {
        // সার্ভার থেকে আসা এরর মেসেজ দেখার জন্য এটি সহায়ক
        throw "Server Error: ${response.statusCode}";
      }
    } catch (e) {
      print("Instagram Service Error: $e");
      rethrow; 
    }
  }
}