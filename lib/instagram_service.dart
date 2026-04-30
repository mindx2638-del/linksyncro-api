import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

class InstagramService {
  // আপনার রেন্ডার লিঙ্কগুলো এখানে সিরিয়ালি যোগ করবেন
  final List<String> _apiBaseUrls = [
    "https://linksyncro-api-8itj.onrender.com",
    "https://linksyncro-api.onrender.com",
  ];

  static const String _apiKey = "demo_key_123"; 

  bool isInstagramLink(String url) {
    String lowerUrl = url.toLowerCase();
    return lowerUrl.contains("instagram.com");
  }

  Future<Map<String, dynamic>> getVideoDetails(String url) async {
    String targetUrl = url.trim();
    String? lastErrorMessage;

    // লুপের মাধ্যমে প্রতিটি রেন্ডার লিঙ্ক চেক করা হবে
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
          // সাকসেসফুলি ডাটা পেলে সরাসরি রিটার্ন করবে
          return jsonDecode(utf8.decode(response.bodyBytes));
        } else {
          // যদি এই সার্ভারে সমস্যা হয় (যেমন: 429, 500, 503), তবে পরবর্তী সার্ভার ট্রাই করবে
          lastErrorMessage = "Server (${baseUrl}) Error: ${response.statusCode}";
          continue; 
        }
      } catch (e) {
        // টাইমআউট বা নেটওয়ার্ক এরর হলে পরের লিঙ্কে যাবে
        if (e is TimeoutException) {
          lastErrorMessage = "Request timed out on $baseUrl";
        } else {
          lastErrorMessage = e.toString();
        }
        continue; 
      }
    }
    
    // যদি সব সার্ভারই ট্রাই করার পর ব্যর্থ হয়
    throw lastErrorMessage ?? "ইনস্টাগ্রাম ভিডিওর তথ্য পাওয়া যায়নি। সব সার্ভার বিজি।";
  }
}