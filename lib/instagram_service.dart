import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

class InstagramService {
  // ১. একাধিক এপিআই লিঙ্কের লিস্ট (Primary ও Backup)
  // আপনার জেনারেট করা রেলওয়ে লিঙ্কটি এখানে প্রথম অপশন হিসেবে দেওয়া হয়েছে
  final List<String> _apiBaseUrls = [
    "https://linksyncro-api-production.up.railway.app", // Railway (Primary)
    "https://linksyncro-api.onrender.com",             // Render (Backup)
  ];
  
  // API Key (আপনার পাইথন ব্যাকএন্ডের সাথে মিল রেখে)
  static const String _apiKey = "demo_key_123"; 

  // লিঙ্কটি ইনস্টাগ্রামের কি না তা চেক করা
  bool isInstagramLink(String url) {
    String lowerUrl = url.toLowerCase();
    return lowerUrl.contains("instagram.com");
  }

  // ২. সার্ভার থেকে ডাটা আনার উন্নত লজিক
  Future<Map<String, dynamic>> getVideoDetails(String url) async {
    String targetUrl = url.trim();
    String? lastErrorMessage;

    // প্রতিটি সার্ভার লিঙ্ক চেক করার জন্য লুপ
    for (String baseUrl in _apiBaseUrls) {
      try {
        // URL এর শেষে /get_media যোগ করা হয়েছে
        final uri = Uri.parse("$baseUrl/get_media?url=${Uri.encodeComponent(targetUrl)}");

        final response = await http.get(
          uri,
          headers: {
            "x-api-key": _apiKey,
            "Accept": "application/json",
          },
        ).timeout(const Duration(seconds: 40)); // প্রতিটি সার্ভারের জন্য সময়সীমা

        if (response.statusCode == 200) {
          // UTF-8 ডিকোডিং নিশ্চিত করা হয়েছে যাতে বাংলা বা বিশেষ ক্যারেক্টার ঠিক থাকে
          return jsonDecode(utf8.decode(response.bodyBytes));
        } else if (response.statusCode == 429) {
          lastErrorMessage = "সার্ভার লিমিট শেষ (Rate Limit)।";
          continue; // পরের সার্ভার ট্রাই করবে
        } else {
          lastErrorMessage = "সার্ভার এরর: ${response.statusCode}";
          continue;
        }
      } catch (e) {
        if (e is TimeoutException) {
          lastErrorMessage = "সার্ভার রেসপন্স দিচ্ছে না (Timeout)।";
        } else {
          lastErrorMessage = e.toString();
        }
        // কানেকশন ফেল করলে লুপ পরের লিঙ্কে চলে যাবে
        continue; 
      }
    }

    // যদি কোনো লিঙ্কই কাজ না করে তবে চূড়ান্ত এরর থ্রো করবে
    throw lastErrorMessage ?? "ইনস্টাগ্রাম ভিডিওর তথ্য পাওয়া যাচ্ছে না।";
  }
}