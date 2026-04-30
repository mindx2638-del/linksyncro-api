import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

class FacebookService {
  
  final List<String> _apiBaseUrls = [
    "https://linksyncro-api-production.up.railway.app", // Railway (Primary)
    "https://linksyncro-api.onrender.com",             // Render (Backup)
  ];
  
  // API Key (আপনার ব্যাকএন্ডের সাথে মিল রেখে)
  static const String _apiKey = "demo_key_123"; 

  // ফেসবুক লিঙ্ক চেনার লজিক (অপরিবর্তিত রাখা হয়েছে)
  bool isFacebookLink(String url) {
    String lowerUrl = url.toLowerCase();
    return lowerUrl.contains("facebook.com") || 
           lowerUrl.contains("fb.watch") || 
           lowerUrl.contains("fb.com");
  }

  Future<Map<String, String>> getVideoDetails(String url) async {
    String targetUrl = url.trim();
    String? lastErrorMessage;

    // ২. লুপ চালিয়ে প্রতিটি সার্ভার চেক করা হবে
    for (String baseUrl in _apiBaseUrls) {
      try {
        final uri = Uri.parse("$baseUrl/get_media?url=${Uri.encodeComponent(targetUrl)}");
        
        final response = await http.get(
          uri,
          headers: {
            "x-api-key": _apiKey,
            "Accept": "application/json",
          },
        ).timeout(const Duration(seconds: 35)); // প্রতিটি সার্ভারের জন্য অপ্টিমাইজড টাইমআউট

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
            // যদি এপিআই থেকে সাকসেস না আসে, তবে এরর মেসেজ স্টোর করে পরের সার্ভারে যাবে
            lastErrorMessage = data['message'];
            continue;
          }
        } else if (response.statusCode == 401) {
          throw "Invalid or unauthorized API Key."; // API Key ভুল থাকলে সাথে সাথে থামবে
        } else if (response.statusCode == 429) {
          lastErrorMessage = "সার্ভার লিমিট শেষ (Rate Limit)।";
          continue; // পরের সার্ভার ট্রাই করবে
        }
      } catch (e) {
        if (e is TimeoutException) {
          lastErrorMessage = "সার্ভার রেসপন্স দিচ্ছে না (Timeout)।";
        } else {
          lastErrorMessage = e.toString();
        }
        // কোনো এরর হলে লুপ থামবে না, পরের সার্ভার চেক করবে
        continue; 
      }
    }

    throw lastErrorMessage ?? "সার্ভারে সংযোগ দেওয়া যাচ্ছে না। দয়া করে লিঙ্কটি পাবলিক কি না চেক করুন।";
  }
}