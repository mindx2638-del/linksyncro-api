import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubeService {
  // আপনার দেওয়া API এন্ডপয়েন্ট এবং কী
  static const String _apiUrl = "https://linksyncro-api.onrender.com/get_media";
  static const String _apiKey = "demo_key_123";

  final YoutubeExplode _yt = YoutubeExplode();

  // ১. URL ভ্যালিডেশন (আগের লজিক ঠিক আছে)
  bool isYouTubeLink(String url) {
    if (url.isEmpty) return false;
    final String cleanUrl = url.trim().replaceAll(RegExp(r'[à¥¤â€”\s]+$'), '');
    final uri = Uri.tryParse(cleanUrl);
    if (uri == null) return false;
    return uri.host.contains('youtube.com') || uri.host.contains('youtu.be');
  }

  // ২. ভিডিও ডিটেইলস ফেচ করা (API লজিক ইন্টিগ্রেট করা হয়েছে)
  Future<Map<String, dynamic>> getVideoDetails(String url) async {
    try {
      // API রিকোয়েস্ট পাঠানো হচ্ছে
      final response = await http.get(
        Uri.parse("$_apiUrl?url=${Uri.encodeComponent(url.trim())}"),
        headers: {
          "x-api-key": _apiKey, // আপনার API Key যোগ করা হলো
          "Accept": "application/json",
        },
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['status'] == 'success') {
          return {
            'url': data['url'],
            'title': data['title'] ?? "YouTube_Video",
            'thumbnail': data['thumbnail'],
            'source': "YouTube",
          };
        } else {
          throw data['message'] ?? "Failed to fetch video details.";
        }
      } else {
        // যদি API ফেইল করে, তাহলে চাইলে আপনি এখান থেকে লাইব্রেরি ব্যাকআপ হিসেবে ব্যবহার করতে পারেন
        // অথবা সরাসরি এরর দেখাতে পারেন
        throw "Server Error: ${response.statusCode}";
      }
    } catch (e) {
      throw "Could not retrieve YouTube video: $e";
    }
  }

  // ৩. এক্সট্রাকশন লজিকটি সেভ থাকল (প্রয়োজনে ব্যবহারের জন্য)
  String? _extractVideoId(String url) {
    // আগের আইডি এক্সট্রাকশন লজিক এখানে রাখতে পারেন
    // ... আপনার আগের লজিক ...
    return null; 
  }

  void close() {
    _yt.close();
  }
}