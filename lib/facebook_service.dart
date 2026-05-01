import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

class FacebookService {
  // ১. একাধিক রেন্ডার সার্ভার লিঙ্কের লিস্ট
  final List<String> _apiUrls = [
    "https://linksyncro-api-1.onrender.com/get_media",
  ];
  
  // API Key (সব সার্ভারে একই কী ব্যবহার করা ভালো)
  static const String _apiKey = "demo_key_123"; 

  // ফেসবুক লিঙ্ক চেনার লজিক
  bool isFacebookLink(String url) {
    String lowerUrl = url.toLowerCase();
    return lowerUrl.contains("facebook.com") || 
           lowerUrl.contains("fb.watch") || 
           lowerUrl.contains("fb.com");
  }

  Future<Map<String, String>> getVideoDetails(String url) async {
    String targetUrl = url.trim();
    String lastErrorMessage = "Could not retrieve video.";

    // ২. লুপের মাধ্যমে প্রতিটি সার্ভার চেক করা
    for (int i = 0; i < _apiUrls.length; i++) {
      String currentUrl = _apiUrls[i];
      
      try {
        final response = await http.get(
          Uri.parse("$currentUrl?url=${Uri.encodeComponent(targetUrl)}"),
          headers: {
            "x-api-key": _apiKey,
            "Accept": "application/json",
          },
        ).timeout(const Duration(seconds: 25)); // প্রতি সার্ভারের জন্য ২৫ সেকেন্ড সময়

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          
          if (data['status'] == 'success') {
            // যদি সাকসেস হয়, তবে এখান থেকেই ডাটা রিটার্ন করবে এবং লুপ থেমে যাবে
            return {
              'url': data['url']?.toString() ?? "",
              'title': data['title']?.toString() ?? "FB_Video_${DateTime.now().millisecondsSinceEpoch}",
              'thumbnail': data['thumbnail']?.toString() ?? "", 
              'source': data['source']?.toString() ?? "Facebook",
            };
          } else {
            lastErrorMessage = data['message'] ?? "Video details not found on Server ${i+1}.";
          }
        } else if (response.statusCode == 401) {
          lastErrorMessage = "Unauthorized: Invalid API Key on Server ${i+1}.";
        } else if (response.statusCode == 429) {
          lastErrorMessage = "Rate limit hit on Server ${i+1}.";
        } else {
          lastErrorMessage = "Server ${i+1} returned error: ${response.statusCode}";
        }

        // যদি এই সার্ভারে কাজ না হয়, লুপ অটোমেটিক পরের currentUrl এ যাবে
        print("Server ${i+1} failed, trying next one...");

      } catch (e) {
        if (e is TimeoutException) {
          lastErrorMessage = "Server ${i+1} timed out.";
        } else {
          lastErrorMessage = "Connection error with Server ${i+1}.";
        }
        print("Error with Server ${i+1}: $e");
        // এরর হলেও লুপ থামবে না, পরের সার্ভারে ট্রাই করবে
        continue;
      }
    }

    // ৩. যদি সব সার্ভার ট্রাই করার পরও কোনো রেজাল্ট না পাওয়া যায়
    throw lastErrorMessage;
  }
}