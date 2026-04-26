import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// 1. Validate YouTube URL
  bool isYouTubeLink(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;

    return uri.host.contains('youtube.com') ||
        uri.host.contains('youtu.be');
  }

  /// 2. Extract Video ID
  String? _extractVideoId(String url) {
    try {
      final uri = Uri.parse(url.trim());

      if (uri.host.contains('youtu.be')) {
        return uri.pathSegments.isNotEmpty
            ? uri.pathSegments.first
            : null;
      }

      if (uri.queryParameters.containsKey('v')) {
        return uri.queryParameters['v'];
      }

      for (final segment in uri.pathSegments) {
        if (segment.length == 11) return segment;
      }

      final regExp = RegExp(r'(?:v=|\/)([0-9A-Za-z_-]{11})');
      final match = regExp.firstMatch(url);
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }

  /// 3. Get BEST QUALITY VIDEO (UP TO 4K)
  Future<Map<String, String>> getVideoDetails(String url) async {
    try {
      final videoId = _extractVideoId(url);

      if (videoId == null) {
        throw "Invalid YouTube link.";
      }

      final video = await _yt.videos.get(videoId);

      if (video.isLive) {
        throw "Live video cannot be downloaded.";
      }

      final manifest =
          await _yt.videos.streamsClient.getManifest(videoId);

      String? streamUrl;

      /// 🔥 BEST QUALITY VIDEO ONLY (4K SUPPORT)
      if (manifest.videoOnly.isNotEmpty) {
        final streams = manifest.videoOnly.toList();

        // 🔥 SORT BY RESOLUTION (STRING SAFE METHOD)
        streams.sort((a, b) {
          int getRes(String q) {
            if (q.contains('2160')) return 2160; // 4K
            if (q.contains('1440')) return 1440;
            if (q.contains('1080')) return 1080;
            if (q.contains('720')) return 720;
            if (q.contains('480')) return 480;
            if (q.contains('360')) return 360;
            return 0;
          }

          return getRes(b.videoQuality.toString())
              .compareTo(getRes(a.videoQuality.toString()));
        });

        streamUrl = streams.first.url.toString();
      }

      /// fallback (rare case)
      else if (manifest.muxed.isNotEmpty) {
        streamUrl =
            manifest.muxed.withHighestBitrate().url.toString();
      }

      if (streamUrl == null) {
        throw "No stream found.";
      }

      return {
        'title': _safeFileName(video.title),
        'url': streamUrl,
        'thumbnail': video.thumbnails.highResUrl,
        'author': video.author,
      };
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