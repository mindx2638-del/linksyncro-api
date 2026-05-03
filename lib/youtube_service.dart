import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:flutter/foundation.dart';

class YouTubeService {
  // আপনার রেন্ডার সার্ভার লিস্ট (FastAPI Backend)
  final List<String> _apiBaseUrls = [
    "https://linksyncro-api-1.onrender.com",       // mindx2638
    "https://linksyncro-api-f1k4.onrender.com",    // linksyncrono 1 
    "https://linksyncro-api-b08a.onrender.com",    // linksyncrono 2
    "https://linksyncro-api-vmm6.onrender.com",    // linksyncro 3
    "https://linksyncro-api-cdll.onrender.com",    // linksyncro 4
  ];

  static const String _apiKey = "demo_key_123"; 

  // ১. ইউটিউব লিংক কি না তা যাচাই করার লজিক
  bool isYouTubeLink(String url) {
    if (url.isEmpty) return false;
    final String cleanUrl = url.trim().toLowerCase();
    return cleanUrl.contains("youtube.com") || 
           cleanUrl.contains("youtu.be") || 
           cleanUrl.contains("youtube-nocookie.com");
  }

  // ২. ভিডিও আইডি বা প্যারামিটার ক্লিন করা (ইউআরএল ক্লিনিং)
  String _prepareUrl(String url) {
    String cleanUrl = url.trim();
    // ইউটিউব শর্টস বা সাধারণ ভিডিওর শেষে ট্র্যাকিং প্যারামিটার (si, feature) রিমুভ করা
    if (cleanUrl.contains("?si=")) {
      cleanUrl = cleanUrl.split("?si=")[0];
    }
    return cleanUrl;
  }

  // ৩. মূল গেট ভিডিও ডিটেইলস ফাংশন (Fallback Mechanism সহ)
  Future<Map<String, String>> getVideoDetails(String url) async {
    final String targetUrl = _prepareUrl(url);
    String? lastErrorMessage;

    // সার্ভার লুপ - একটি ফেল করলে পরেরটিতে ট্রাই করবে
    for (String baseUrl in _apiBaseUrls) {
      try {
        debugPrint("Trying YouTube extraction on: $baseUrl");
        
        final uri = Uri.parse("$baseUrl/get_media?url=${Uri.encodeComponent(targetUrl)}");
        
        final response = await http.get(
          uri,
          headers: {
            "x-api-key": _apiKey,
            "Accept": "application/json",
          },
        ).timeout(const Duration(seconds: 15)); // ১৫ সেকেন্ড টাইমআউট

        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          
          if (data['status'] == 'success') {
            return {
              'url': data['url']?.toString() ?? "",
              'title': _safeFileName(data['title']?.toString() ?? "YT_Video_${DateTime.now().millisecondsSinceEpoch}"),
              'thumbnail': data['thumbnail']?.toString() ?? "", 
              'source': data['source']?.toString() ?? "YouTube",
            };
          } else {
            lastErrorMessage = data['message'] ?? "Server couldn't process the link.";
            continue; 
          }
        } else if (response.statusCode == 401) {
          throw "Invalid API Key - check your backend configuration.";
        } else if (response.statusCode == 429) {
          lastErrorMessage = "Rate limit reached on this server.";
          continue;
        } else {
          lastErrorMessage = "Server Error: ${response.statusCode}";
          continue;
        }

      } catch (e) {
        if (e is TimeoutException) {
          lastErrorMessage = "Connection timed out.";
        } else {
          lastErrorMessage = e.toString();
        }
        debugPrint("YouTube Service error on $baseUrl: $e");
        continue; // পরের সার্ভারে যাবে
      }
    }

    // সব সার্ভার ট্রাই করার পর যদি কাজ না হয়
    throw lastErrorMessage ?? "Unable to extract video. The content might be age-restricted or private.";
  }

  // ৪. ফাইল সিস্টেমের জন্য নাম ক্লিন করা (অপরিবর্তিত)
  String _safeFileName(String input) {
    return input.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
  }
}