import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubeService {
  final YoutubeExplode _yt = YoutubeExplode();
  
  // আপনার রেন্ডার ব্যাকএন্ড ইউআরএল (এখানে সেট করুন)
  final String _backendUrl = "https://linksyncro-api.onrender.com/get_media";
  final String _apiKey = "demo_key_123"; // আপনার রেন্ডারে সেট করা কি

  /// 1. Validate URL
  bool isYouTubeLink(String url) {
    if (url.isEmpty) return false;
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    return uri.host.contains('youtube.com') || uri.host.contains('youtu.be');
  }

  /// 2. Get Metadata (Title, Thumbnail, Author) - দ্রুত কাজ করবে
  Future<Map<String, String>> fetchVideoMetadata(String url) async {
    try {
      final videoId = VideoId.parseVideoId(url);
      final video = await _yt.videos.get(videoId);
      
      return {
        'title': video.title,
        'author': video.author,
        'thumbnail': video.thumbnails.highResUrl,
        'videoId': videoId.value,
      };
    } catch (e) {
      throw "মেটাডেটা লোড করতে সমস্যা হয়েছে: $e";
    }
  }

  /// 3. Get HD Download Link - রেন্ডার ব্যাকএন্ড থেকে আসবে
  Future<String> getHdDownloadUrl(String url) async {
    try {
      final response = await http.get(
        Uri.parse("$_backendUrl?url=${Uri.encodeComponent(url)}"),
        headers: {"x-api-key": _apiKey},
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['url']; // ব্যাকএন্ড থেকে পাওয়া আসল এইচডি লিঙ্ক
      } else {
        throw "সার্ভার এরর: ${response.statusCode}";
      }
    } catch (e) {
      throw "এইচডি লিঙ্ক জেনারেট করতে ব্যর্থ: $e";
    }
  }

  /// 4. Dispose
  void close() {
    _yt.close();
  }
}