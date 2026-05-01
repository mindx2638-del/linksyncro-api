import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

class FacebookService {
  final List<String> _apiBaseUrls = [
    "https://linksyncro-api-f1k4.onrender.com", 
    "https://linksyncro-api-1.onrender.com",
    "https://linksyncro-api-b08a.onrender.com",
  ];

  static const String _apiKey = "demo_key_123"; 

  // সব ধরণের ফেসবুক ডোমেইন চেক করার লজিক
  bool isFacebookLink(String url) {
    String lowerUrl = url.toLowerCase();
    return lowerUrl.contains("facebook.com") || 
           lowerUrl.contains("fb.watch") || 
           lowerUrl.contains("fb.com") ||
           lowerUrl.contains("web.facebook.com");
  }

  // শেয়ারিং লিংক থেকে আসল ভিডিও লিংক বের করার ফাংশন
  Future<String> _resolveRedirects(String url) async {
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url))
        ..followRedirects = false; // আমরা ম্যানুয়ালি চেক করব
      
      final response = await client.send(request).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 301 || response.statusCode == 302) {
        final location = response.headers['location'];
        if (location != null) return location;
      }
      return url;
    } catch (e) {
      return url; // কোনো সমস্যা হলে মূল ইউআরএল ব্যবহার করবে
    }
  }

  Future<Map<String, String>> getVideoDetails(String url) async {
    String targetUrl = url.trim();

    // ১. শেয়ারিং লিংকের আসল রূপ বের করা
    if (targetUrl.contains("facebook.com/share")) {
      targetUrl = await _resolveRedirects(targetUrl);
    }

    // ২. লিংকের ট্র্যাকিং প্যারামিটার মুছে ফেলা (পরিষ্কার করা)
    if (targetUrl.contains("?")) {
      targetUrl = targetUrl.split("?")[0];
    }

    String? lastErrorMessage;

    for (String baseUrl in _apiBaseUrls) {
      try {
        final uri = Uri.parse("$baseUrl/get_media?url=${Uri.encodeComponent(targetUrl)}");
        
        final response = await http.get(
          uri,
          headers: {
            "x-api-key": _apiKey,
            "Accept": "application/json",
          },
        ).timeout(const Duration(seconds: 35));

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
            lastErrorMessage = data['message'];
            continue; 
          }
        } else if (response.statusCode == 401) {
          throw "Invalid or unauthorized API Key."; 
        } else if (response.statusCode == 429) {
          lastErrorMessage = "Server rate limit exceeded.";
          continue; 
        }
      } catch (e) {
        if (e is TimeoutException) {
          lastErrorMessage = "Server request timed out.";
        } else {
          lastErrorMessage = e.toString();
        }
        continue; 
      }
    }
    throw lastErrorMessage ?? "Unable to connect to servers. Please ensure the link is public.";
  }
}