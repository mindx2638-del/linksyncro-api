import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:flutter/foundation.dart'; // debugPrint ব্যবহারের জন্য

class InstagramService {
  // আপনার এপিআই সার্ভার লিস্ট
  final List<String> _apiBaseUrls = [
    "https://linksyncro-api-f1k4.onrender.com",
    "https://linksyncro-api-1.onrender.com",       
    "https://linksyncro-api-b08a.onrender.com",
  ];

  static const String _apiKey = "demo_key_123"; 

  // ইন্সটাগ্রাম লিংক চেক করার লজিক (অপরিবর্তিত)
  bool isInstagramLink(String url) {
    String lowerUrl = url.toLowerCase();
    return lowerUrl.contains("instagram.com");
  }

  Future<Map<String, dynamic>> getVideoDetails(String url) async {
    String targetUrl = url.trim();
    
    // লিংকে কোনো ট্র্যাকিং প্যারামিটার থাকলে তা পরিষ্কার করা (ভালো রেজাল্টের জন্য)
    if (targetUrl.contains("?")) {
      targetUrl = targetUrl.split("?")[0];
    }

    String? lastErrorMessage;

    // সার্ভার লুপ শুরু
    for (String baseUrl in _apiBaseUrls) {
      try {
        final uri = Uri.parse("$baseUrl/get_media?url=${Uri.encodeComponent(targetUrl)}");
        
        // টাইমআউট কমিয়ে ১৫ সেকেন্ড করা হয়েছে যাতে দ্রুত পরের সার্ভারে সুইচ করতে পারে
        final response = await http.get(
          uri,
          headers: {
            "x-api-key": _apiKey,
            "Accept": "application/json",
          },
        ).timeout(const Duration(seconds: 15)); 

        if (response.statusCode == 200) {
          // সফল হলে সরাসরি ডাটা রিটার্ন করবে
          return jsonDecode(utf8.decode(response.bodyBytes));
        } else if (response.statusCode == 401) {
          // এপিআই কি সমস্যা হলে সাথে সাথে এরর দিবে
          throw "Invalid or unauthorized API Key.";
        } else {
          // অন্য কোনো এরর (৪২৯, ৫০০, ৪০৪) হলে পরের সার্ভারে যাবে
          lastErrorMessage = "Server Error: ${response.statusCode}";
          debugPrint("Instagram API failed on $baseUrl: ${response.statusCode}");
          continue; 
        }
      } catch (e) {
        // সার্ভার সাস্পেন্ড থাকলে বা কানেকশন ফেইল করলে এখানে আসবে
        if (e is TimeoutException) {
          lastErrorMessage = "Server request timed out.";
        } else {
          lastErrorMessage = e.toString();
        }
        debugPrint("Instagram Service connection error on $baseUrl: $e");
        continue; // সাইলেন্টলি পরবর্তী ব্যাকআপ সার্ভার ট্রাই করবে
      }
    }

    // সব সার্ভার লুপ শেষে ব্যর্থ হলে এই এররটি দেখাবে
    throw lastErrorMessage ?? "Unable to retrieve Instagram video details. Please check the link.";
  }
}