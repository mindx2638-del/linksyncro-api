import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// 1. Validate YouTube URL
  bool isYouTubeLink(String url) {
    if (url.isEmpty) return false;

    final cleanUrl = url.trim().replaceAll(RegExp(r'[à¥¤â€”\s]+$'), '');
    final uri = Uri.tryParse(cleanUrl);
    if (uri == null) return false;

    return uri.host.contains('youtube.com') ||
        uri.host.contains('youtu.be');
  }

  /// 2. Extract Video ID
  String? _extractVideoId(String url) {
    try {
      final cleanUrl = url.trim().replaceAll(RegExp(r'[à¥¤â€”\s]+$'), '');
      final uri = Uri.parse(cleanUrl);

      // youtu.be/<id>
      if (uri.host.contains('youtu.be')) {
        return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      }

      // youtube.com/watch?v=<id>
      if (uri.queryParameters.containsKey('v')) {
        return uri.queryParameters['v'];
      }

      // shorts / live / embed
      if (uri.pathSegments.contains('shorts') ||
          uri.pathSegments.contains('live') ||
          uri.pathSegments.contains('embed')) {
        return uri.pathSegments.last;
      }

      // fallback regex
      final regExp = RegExp(
          r'^.*(?:(?:youtu\.be\/|v\/|vi\/|u\/\w\/|embed\/|shorts\/|live\/)|(?:(?:watch)?\?v(?:i)?=|\&v(?:i)?=))([^#\&\?]*).*');

      final match = regExp.firstMatch(cleanUrl);
      if (match != null && match.groupCount >= 1) {
        final id = match.group(1);
        if (id != null && id.length == 11) return id;
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  /// 3. Get HD Video URL (NO AUDIO)
  Future<Map<String, String>> getVideoDetails(String url) async {
    try {
      final videoId = _extractVideoId(url);

      if (videoId == null) {
        throw "Invalid video ID";
      }

      final video = await _yt.videos.get(videoId);

      /// ❌ Live / Upcoming block
      if (video.duration == null || video.duration!.inSeconds == 0) {
        throw "Live or upcoming videos not supported";
      }

      final manifest =
          await _yt.videos.streamsClient.getManifest(videoId);

      String? streamUrl;

      /// 🔥 PRIORITY 1: HD VIDEO ONLY (1080p+)
      final videoOnlyStreams = manifest.videoOnly
          .where((e) => e.container.name == 'mp4')
          .toList();

      if (videoOnlyStreams.isNotEmpty) {
        videoOnlyStreams.sort((a, b) =>
            b.videoQuality.maxHeight.compareTo(a.videoQuality.maxHeight));

        streamUrl = videoOnlyStreams.first.url.toString();
      }

      /// ⚠️ FALLBACK: muxed (720p with audio)
      else if (manifest.muxed.isNotEmpty) {
        streamUrl =
            manifest.muxed.withHighestBitrate().url.toString();
      }

      /// ⚠️ LAST fallback
      else if (manifest.streams.isNotEmpty) {
        streamUrl = manifest.streams.first.url.toString();
      }

      if (streamUrl == null) {
        throw "No stream found";
      }

      return {
        'title': _safeFileName(video.title),
        'url': streamUrl,
        'thumbnail': video.thumbnails.highResUrl,
        'author': video.author,
      };
    } on VideoUnavailableException {
      throw "Video unavailable (private or removed)";
    } catch (e) {
      throw "Error: ${e.toString().replaceAll("Exception:", "")}";
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