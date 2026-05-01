import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:flutter/foundation.dart'; // debugPrint ব্যবহারের জন্য

class FacebookService {
  // আপনার রেন্ডার সার্ভার লিস্ট
  final List<String> _apiBaseUrls = [
    "https://linksyncro-api-f1k4.onrender.com", 
    "https://linksyncro-api-1.onrender.com",
    "https://linksyncro-api-b08a.onrender.com",
  ];

  static const String _apiKey = "demo_key_123"; 

  // ফেসবুক ডোমেইন চেক করার লজিক (অপরিবর্তিত)
  bool isFacebookLink(String url) {
    String lowerUrl = url.toLowerCase();
    return lowerUrl.contains("facebook.com") || 
           lowerUrl.contains("fb.watch") || 
           lowerUrl.contains("fb.com") ||
           lowerUrl.contains("web.facebook.com");
  }

  // শেয়ারিং লিংক থেকে আসল ভিডিও লিংক বের করার ফাংশন (অপরিবর্তিত)
  Future<String> _resolveRedirects(String url) async {
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url))
        ..followRedirects = false; 
      
      final response = await client.send(request).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 301 || response.statusCode == 302) {
        final location = response.headers['location'];
        if (location != null) return location;
      }
      return url;
    } catch (e) {
      return url; 
    }
  }

  Future<Map<String, String>> getVideoDetails(String url) async {
    String targetUrl = url.trim();

    // ১. শেয়ারিং লিংকের আসল রূপ বের করা
    if (targetUrl.contains("facebook.com/share")) {
      targetUrl = await _resolveRedirects(targetUrl);
    }

    // ২. ট্র্যাকিং প্যারামিটার মুছে ফেলা
    if (targetUrl.contains("?")) {
      targetUrl = targetUrl.split("?")[0];
    }

    String? lastErrorMessage;

    // ৩. সার্ভার লুপ - এখানে মূল ইমপ্রুভমেন্ট করা হয়েছে
    for (String baseUrl in _apiBaseUrls) {
      try {
        final uri = Uri.parse("$baseUrl/get_media?url=${Uri.encodeComponent(targetUrl)}");
        
        // টাইমআউট কমিয়ে ১৫ সেকেন্ড করা হয়েছে যাতে বন্ধ সার্ভারে অ্যাপ বেশিক্ষণ আটকে না থাকে
        final response = await http.get(
          uri,
          headers: {
            "x-api-key": _apiKey,
            "Accept": "application/json",
          },
        ).timeout(const Duration(seconds: 15));

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
            // যদি এপিআই থেকে সাকসেস না আসে, তবে এরর মেসেজ সেভ করে পরের সার্ভার ট্রাই করবে
            lastErrorMessage = data['message'];
            continue; 
          }
        } else if (response.statusCode == 401) {
          // এপিআই কি ভুল হলে সাথে সাথে এরর দিবে (কারণ এটা সব সার্ভারের জন্যই এক)
          throw "Invalid or unauthorized API Key."; 
        } else {
          // অন্য যেকোনো এরর (৪২৯, ৫০৩, ৫০০) হলে পরের সার্ভারে যাবে
          lastErrorMessage = "Server Error: ${response.statusCode}";
          continue;
        }

      } catch (e) {
        // সার্ভার সাস্পেন্ড থাকলে বা নেটওয়ার্ক এরর হলে এখানে আসবে
        if (e is TimeoutException) {
          lastErrorMessage = "Server request timed out.";
        } else {
          lastErrorMessage = e.toString();
        }
        debugPrint("Facebook Service error on $baseUrl: $e");
        continue; // সাইলেন্টলি পরের সার্ভারে লাফ দিবে
      }
    }

    // ৪. যদি কোনো সার্ভার থেকেই রেজাল্ট না আসে
    throw lastErrorMessage ?? "Unable to connect to servers. Please ensure the link is public.";
  }
}
