import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// =============================
/// Custom Exception
/// =============================
class YouTubeException implements Exception {
  final String message;
  YouTubeException(this.message);

  @override
  String toString() => message;
}

/// =============================
/// YouTube Service
/// =============================
class YouTubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  final String _backendUrl = "https://linksyncro-api.onrender.com/get_media";
  final String _apiKey = "demo_key_123";

  /// =============================
  /// 1. Validate YouTube URL (All types)
  /// =============================
  bool isYouTubeLink(String url) {
    if (url.trim().isEmpty) return false;

    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;

    final host = uri.host.toLowerCase();

    return host.contains('youtube.com') ||
        host.contains('youtu.be') ||
        host.contains('m.youtube.com') ||
        host.contains('music.youtube.com');
  }

  /// =============================
  /// 2. Extract Video ID safely (All formats)
  /// =============================
  String? _extractVideoId(String url) {
    try {
      return VideoId(url).value;
    } catch (_) {
      return null;
    }
  }

  /// =============================
  /// 3. Fetch Metadata (Safe & Stable)
  /// =============================
  Future<Map<String, String>> fetchVideoMetadata(String url) async {
    try {
      if (!isYouTubeLink(url)) {
        throw YouTubeException("Invalid YouTube URL");
      }

      final videoId = _extractVideoId(url);
      if (videoId == null) {
        throw YouTubeException("Video ID not found");
      }

      final video = await _yt.videos.get(videoId);

      return {
        'title': video.title ?? "No Title",
        'author': video.author ?? "Unknown",
        'thumbnail': video.thumbnails.highResUrl ??
            video.thumbnails.mediumResUrl ??
            "",
        'videoId': videoId,
      };
    } catch (e) {
      throw YouTubeException("Problem loading metadata: $e");
    }
  }

  /// =============================
  /// 4. Get HD Download URL (Backend Safe)
  /// =============================
  Future<String> getHdDownloadUrl(String url) async {
  try {
    if (!isYouTubeLink(url)) {
      throw YouTubeException("Invalid YouTube URL");
    }

    final String encodedUrl = Uri.encodeComponent(url);
    final String fullUrl = "$_backendUrl?url=$encodedUrl";
    
    print("Sending Request to: $fullUrl"); // চেক ১: ইউআরএল ঠিক আছে কিনা

    final response = await http.get(
      Uri.parse(fullUrl), 
      headers: {"x-api-key": _apiKey}
    ).timeout(const Duration(seconds: 45));

    print("Response Status Code: ${response.statusCode}"); // চেক ২: স্ট্যাটাস কোড কি ২০০?
    print("Response Body: ${response.body}"); // চেক ৩: সার্ভার আসলে কি বলছে?

    if (response.statusCode != 200) {
      throw YouTubeException("Server Error: ${response.statusCode}");
    }

    final data = jsonDecode(response.body);

    if (data == null || data['url'] == null) {
      throw YouTubeException("Invalid server response");
    }

    return data['url'];
  } catch (e) {
    print("FATAL ERROR in getHdDownloadUrl: $e"); // চেক ৪: আসল এররটা এখানে দেখাবে
    throw YouTubeException("Failed to fetch hd link: $e");
  }
}

  /// =============================
  /// 5. Dispose (Memory Safe)
  /// =============================
  void close() {
    _yt.close();
  }
}