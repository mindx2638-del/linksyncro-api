import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

class FacebookService {
  // আপনার ১০টি রেন্ডার অ্যাকাউন্টের লিঙ্ক এখানে সিরিয়ালি বসাবেন
  final List<String> _apiBaseUrls = [
   "https://linksyncro-api-b08a.onrender.com",
  ];

  static const String _apiKey = "demo_key_123"; 

  bool isFacebookLink(String url) {
    String lowerUrl = url.toLowerCase();
    return lowerUrl.contains("facebook.com") || 
           lowerUrl.contains("fb.watch") || 
           lowerUrl.contains("fb.com");
  }

  Future<Map<String, String>> getVideoDetails(String url) async {
    String targetUrl = url.trim();
    String? lastErrorMessage;

    // লুপটি প্রতিটি সার্ভার লিঙ্ক চেক করবে
    for (String baseUrl in _apiBaseUrls) {
      try {
        final uri = Uri.parse("$baseUrl/get_media?url=${Uri.encodeComponent(targetUrl)}");
        
        final response = await http.get(
          uri,
          headers: {
            "x-api-key": _apiKey,
            "Accept": "application/json",
          },
        ).timeout(const Duration(seconds: 40)); // রেন্ডার মাঝে মাঝে সময় নিতে পারে তাই ৪০ সেকেন্ড দিলাম

        // যদি এই সার্ভারটি ঠিক থাকে (Status 200)
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          
          if (data['status'] == 'success') {
            return {
              'url': data['url']?.toString() ?? "",
              'title': data['title']?.toString() ?? "FB_Video_${DateTime.now().millisecondsSinceEpoch}",
              'thumbnail': data['thumbnail']?.toString() ?? "", 
              'source': data['source']?.toString() ?? "Facebook",
            };
          } else {
            // যদি এপিআই থেকে এরর আসে, পরের সার্ভার ট্রাই করবে
            lastErrorMessage = data['message'];
            continue; 
          }
        } 
        // যদি সার্ভার ডাউন থাকে (যেমন ১০০ GB শেষ হয়ে গেলে ৫-৩ বা ৪-৪ এরর দিবে)
        else {
          lastErrorMessage = "Server error: ${response.statusCode}";
          continue; // পরের লিঙ্কে চলে যাবে
        }
      } catch (e) {
        // কানেকশন ফেল করলে বা টাইম আউট হলে পরের সার্ভার ট্রাই করবে
        if (e is TimeoutException) {
          lastErrorMessage = "Request timed out on this server.";
        } else {
          lastErrorMessage = e.toString();
        }
        continue; // অটোমেটিক পরের রেন্ডার লিঙ্কে চলে যাবে
      }
    }
    
    // যদি সব সার্ভারই ফেল করে, তখন এই এররটি দেখাবে
    throw "সবগুলো সার্ভার এই মুহূর্তে বিজি অথবা লিমিট শেষ। কিছুক্ষণ পর চেষ্টা করুন।";
  }
}
