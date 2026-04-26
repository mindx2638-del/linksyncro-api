import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// 1. Validate YouTube URL
  bool isYouTubeLink(String url) {
    if (url.isEmpty) return false;

    final String cleanUrl =
        url.trim().replaceAll(RegExp(r'[à¥¤â€”\s]+$'), '');

    final uri = Uri.tryParse(cleanUrl);
    if (uri == null) return false;

    return uri.host.contains('youtube.com') ||
        uri.host.contains('youtu.be');
  }

  /// 2. Extract Video ID
  String? _extractVideoId(String url) {
    try {
      final String cleanUrl =
          url.trim().replaceAll(RegExp(r'[à¥¤â€”\s]+$'), '');

      final uri = Uri.parse(cleanUrl);

      if (uri.host.contains('youtu.be')) {
        return uri.pathSegments.isNotEmpty
            ? uri.pathSegments.first
            : null;
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
        r'^.*(?:(?:youtu\.be\/|v\/|vi\/|u\/\w\/|embed\/|shorts\/|live\/)|(?:(?:watch)?\?v(?:i)?=|\&v(?:i)?=))([^#\&\?]*).*',
      );

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

  /// 3. Get BEST HD VIDEO ONLY STREAM
  Future<Map<String, String>> getVideoDetails(String url) async {
    try {
      final videoId = _extractVideoId(url);

      if (videoId == null) {
        throw "Invalid video ID. Please check the URL.";
      }

      final video = await _yt.videos.get(videoId);

      if (video.duration == null ||
          video.duration!.inSeconds == 0) {
        throw "Live or upcoming videos cannot be downloaded.";
      }

      final manifest =
          await _yt.videos.streamsClient.getManifest(videoId);

      String? streamUrl;

      /// 🔥 HD VIDEO ONLY PRIORITY SYSTEM (FIXED)
      if (manifest.videoOnly.isNotEmpty) {
  final videoStreams = manifest.videoOnly.toList();

  int getQualityScore(VideoQuality q) {
    final label = q.toString().toLowerCase();

    if (label.contains('1080')) return 3;
    if (label.contains('720')) return 2;
    if (label.contains('480')) return 1;
    if (label.contains('360')) return 0;

    return -1;
  }

  videoStreams.sort((a, b) =>
      getQualityScore(b.videoQuality)
          .compareTo(getQualityScore(a.videoQuality)));

  streamUrl = videoStreams.first.url.toString();
}

      /// fallback
      else if (manifest.streams.isNotEmpty) {
        streamUrl = manifest.streams.first.url.toString();
      }

      if (streamUrl == null) {
        throw "No downloadable HD stream found.";
      }

      return _buildResponse(video, streamUrl);
    } on VideoUnavailableException {
      throw "Video is unavailable (Private or Removed).";
    } catch (e) {
      throw "Error: ${e.toString().replaceAll("Exception:", "")}";
    }
  }

  /// 4. Response builder
  Map<String, String> _buildResponse(
      Video video, String streamUrl) {
    return {
      'title': _safeFileName(video.title),
      'url': streamUrl,
      'thumbnail': video.thumbnails.highResUrl,
      'author': video.author,
    };
  }

  /// 5. Safe filename
  String _safeFileName(String input) {
    return input
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .trim();
  }

  /// 6. Dispose
  void close() {
    _yt.close();
  }
}