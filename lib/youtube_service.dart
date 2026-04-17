import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  // আপনার নতুন ডকার এপিআই লিঙ্ক
  // Render-এ আপনার নতুন সার্ভিস লিঙ্কটি এখানে ব্যবহার করুন
  final String myApiUrl = "https://linksyncro-api-2.onrender.com/extract?url=";

  /// 1. Validate if the URL is a YouTube link
  bool isYouTubeLink(String url) {
    if (url.isEmpty) return false;
    // Clean unnecessary characters or punctuation from the end of the URL
    final String cleanUrl = url.trim().replaceAll(RegExp(r'[।—\s]+$'), '');
    final uri = Uri.tryParse(cleanUrl);
    if (uri == null) return false;
    return uri.host.contains('youtube.com') || uri.host.contains('youtu.be');
  }

  /// 2. Extract Video ID (আপনার পুরনো সব লজিক এখানে রাখা হয়েছে)
  String? _extractVideoId(String url) {
    try {
      final String cleanUrl = url.trim().replaceAll(RegExp(r'[।—\s]+$'), '');
      final uri = Uri.parse(cleanUrl);

      if (uri.host.contains('youtu.be')) {
        return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      }
      if (uri.queryParameters.containsKey('v')) {
        return uri.queryParameters['v'];
      }
      if (uri.pathSegments.contains('shorts')) {
        return uri.pathSegments.last;
      }
      if (uri.pathSegments.contains('live')) {
        return uri.pathSegments.last;
      }
      if (uri.pathSegments.contains('embed')) {
        return uri.pathSegments.last;
      }

      final RegExp regExp = RegExp(
          r'^.*(?:(?:youtu\.be\/|v\/|vi\/|u\/\w\/|embed\/|shorts\/|live\/)|(?:(?:watch)?\?v(?:i)?=|\&v(?:i)?=))([^#\&\?]*).*');
      final match = regExp.firstMatch(cleanUrl);
      
      if (match != null && match.groupCount >= 1) {
        final String? id = match.group(1);
        if (id != null && id.length == 11) return id;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 3. Get video details and download URL (এখন এটি API ব্যবহার করবে)
  Future<Map<String, String>> getVideoDetails(String url) async {
    try {
      final videoId = _extractVideoId(url);
      if (videoId == null) {
        throw "Invalid video ID. Please check the URL.";
      }

      // ভিডিও টাইটেল এবং থাম্বনেইল এর জন্য আমরা ইউটিউব এক্সপ্লোড ব্যবহার করতে পারি 
      // অথবা সরাসরি এপিআই এর ওপর নির্ভর করতে পারি। এপিআই ব্যবহার করা নিরাপদ।
      final response = await http.get(
        Uri.parse("$myApiUrl${Uri.encodeComponent(url.trim())}")
      ).timeout(const Duration(seconds: 90)); // ৪কে প্রসেসিং-এ সময় লাগে তাই সময় বাড়িয়ে দেওয়া হয়েছে

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (data['status'] == 'success') {
          return {
            'title': _safeFileName(data['title'] ?? "Video_$videoId"),
            'url': data['url'], // এটি আপনার সার্ভারের ডকার জেনারেটেড লিঙ্ক
            'thumbnail': data['thumbnail'] ?? "https://img.youtube.com/vi/$videoId/hqdefault.jpg",
            'author': "YouTube",
          };
        } else {
          throw data['message'] ?? "API could not extract media.";
        }
      } else {
        throw "Server error: ${response.statusCode}. Please try again later.";
      }
    } catch (e) {
      // এপিআই ফেইল করলে একটি ফলব্যাক এরর মেসেজ
      throw "Error: ${e.toString().replaceAll("Exception:", "")}";
    }
  }

  /// 4. Clean filename to avoid FileSystemException (Error 36)
  String _safeFileName(String input) {
    return input.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
  }

  /// 5. Dispose resources
  void close() {
    _yt.close();
  }
}