import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

class InstagramService {
  // ১. আপনার সব রেন্ডার/রেলওয়ে অ্যাকাউন্টের লিঙ্ক এখানে সিরিয়ালি দিন
  final List<String> _apiBaseUrls = [
    "https://linksyncro-api-8itj.onrender.com",
    "https://linksyncro-api.onrender.com",       // Render Acc 1
  ];

  static const String _apiKey = "demo_key_123"; 

  bool isInstagramLink(String url) {
    String lowerUrl = url.toLowerCase();
    // ইনস্টাগ্রাম রিলস বা আইজিটিভি সব সাপোর্ট করার জন্য
    return lowerUrl.contains("instagram.com") || lowerUrl.contains("instagr.am");
  }

  Future<Map<String, dynamic>> getVideoDetails(String url) async {
    String targetUrl = url.trim();
    String? lastErrorMessage;

    // ২. লুপের মাধ্যমে প্রতিটি সার্ভার চেক করবে
    for (String baseUrl in _apiBaseUrls) {
      try {
        final uri = Uri.parse("$baseUrl/get_media?url=${Uri.encodeComponent(targetUrl)}");
        
        final response = await http.get(
          uri,
          headers: {
            "x-api-key": _apiKey,
            "Accept": "application/json",
          },
        ).timeout(const Duration(seconds: 40)); 

        if (response.statusCode == 200) {
          // সফল হলে ডাটা রিটার্ন করবে
          return jsonDecode(utf8.decode(response.bodyBytes));
        } else if (response.statusCode == 429) {
          lastErrorMessage = "Rate limit reached on this server.";
          continue; // পরের সার্ভারে ট্রাই করবে
        } else {
          lastErrorMessage = "Server Error: ${response.statusCode}";
          continue; // অন্য কোনো এরর হলেও পরের সার্ভারে ট্রাই করবে
        }
      } catch (e) {
        if (e is TimeoutException) {
          lastErrorMessage = "Connection timed out.";
        } else {
          lastErrorMessage = e.toString();
        }
        continue; // ফেল করলে পরের লিঙ্কে চলে যাবে
      }
    }
    
    // সব সার্ভার ফেল করলে শেষ এররটি পাঠাবে
    throw lastErrorMessage ?? "Unable to retrieve Instagram video details. Make sure the account is public.";
  }
}