import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// 1. Validate YouTube URL
  bool isYouTubeLink(String url) {
    if (url.isEmpty) return false;

    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;

    return uri.host.contains('youtube.com') ||
        uri.host.contains('youtu.be');
  }

  /// 2. Extract Video ID (FIXED UNIVERSAL)
  String? _extractVideoId(String url) {
    try {
      final uri = Uri.parse(url.trim());

      // youtu.be/<id>
      if (uri.host.contains('youtu.be')) {
        return uri.pathSegments.isNotEmpty
            ? uri.pathSegments.first
            : null;
      }

      // watch?v=<id>
      if (uri.queryParameters.containsKey('v')) {
        return uri.queryParameters['v'];
      }

      // shorts / live / embed
      for (final segment in uri.pathSegments) {
        if (segment.length == 11) return segment;
      }

      // fallback
      final regExp = RegExp(r'(?:v=|\/)([0-9A-Za-z_-]{11})');
      final match = regExp.firstMatch(url);
      return match?.group(1);

    } catch (_) {
      return null;
    }
  }

  /// 3. Get DOWNLOADABLE STREAM (FIXED)
  Future<Map<String, String>> getVideoDetails(String url) async {
    try {
      final videoId = _extractVideoId(url);

      if (videoId == null) {
        throw "Invalid YouTube link.";
      }

      final video = await _yt.videos.get(videoId);

      // live check
      if (video.isLive) {
        throw "Live video cannot be downloaded.";
      }

      final manifest =
          await _yt.videos.streamsClient.getManifest(videoId);

      String? streamUrl;

      /// 🔥 BEST: MUXED (WORKS FOR DOWNLOAD)
      if (manifest.muxed.isNotEmpty) {
        streamUrl =
            manifest.muxed.withHighestBitrate().url.toString();
      }

      /// fallback (rare)
      else if (manifest.streams.isNotEmpty) {
        streamUrl = manifest.streams.first.url.toString();
      }

      if (streamUrl == null) {
        throw "No downloadable stream found.";
      }

      return {
        'title': _safeFileName(video.title),
        'url': streamUrl,
        'thumbnail': video.thumbnails.highResUrl,
        'author': video.author,
      };

    } on VideoUnavailableException {
      throw "Video is unavailable.";
    } catch (e) {
      throw "Error: ${e.toString()}";
    }
  }

  /// 4. Safe filename
  String _safeFileName(String input) {
    return input
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .trim();
  }

  /// 5. Dispose
  void close() {
    _yt.close();
  }
}
