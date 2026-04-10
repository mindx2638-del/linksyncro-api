import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// 1. Validate if the URL is a YouTube link
  bool isYouTubeLink(String url) {
    if (url.isEmpty) return false;
    // Clean unnecessary characters or punctuation from the end of the URL
    final String cleanUrl = url.trim().replaceAll(RegExp(r'[।—\s]+$'), '');
    final uri = Uri.tryParse(cleanUrl);
    if (uri == null) return false;
    return uri.host.contains('youtube.com') || uri.host.contains('youtu.be');
  }

  /// 2. Extract Video ID from different YouTube URL formats
  String? _extractVideoId(String url) {
    try {
      // Remove Bengali punctuation (।, —) or spaces from the end of the URL
      final String cleanUrl = url.trim().replaceAll(RegExp(r'[।—\s]+$'), '');

      final uri = Uri.parse(cleanUrl);

      // a) youtu.be/<id> (Shortened URL)
      if (uri.host.contains('youtu.be')) {
        return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      }

      // b) youtube.com/watch?v=<id> (Normal Desktop URL)
      if (uri.queryParameters.containsKey('v')) {
        return uri.queryParameters['v'];
      }

      // c) youtube.com/shorts/<id> (Shorts URL)
      if (uri.pathSegments.contains('shorts')) {
        return uri.pathSegments.last;
      }

      // d) youtube.com/live/<id> (Live Stream URL)
      if (uri.pathSegments.contains('live')) {
        return uri.pathSegments.last;
      }

      // e) youtube.com/embed/<id> (Embedded URL)
      if (uri.pathSegments.contains('embed')) {
        return uri.pathSegments.last;
      }

      // f) Strong Regex fallback (In case other patterns miss)
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

  /// 3. Get video details and download URL
  Future<Map<String, String>> getVideoDetails(String url) async {
    try {
      final videoId = _extractVideoId(url);
      if (videoId == null) {
        throw "Invalid video ID. Please check the URL.";
      }

      final video = await _yt.videos.get(videoId);

      /// Check if video is Live or Upcoming
      if (video.duration == null || video.duration!.inSeconds == 0) {
        throw "Live or upcoming videos cannot be downloaded.";
      }

      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      String? streamUrl;

      // Priority 1: Muxed Stream (Video + Audio)
      if (manifest.muxed.isNotEmpty) {
        streamUrl = manifest.muxed.withHighestBitrate().url.toString();
      } 
      // Priority 2: Video Only
      else if (manifest.videoOnly.isNotEmpty) {
        streamUrl = manifest.videoOnly.withHighestBitrate().url.toString();
      } 
      // Priority 3: First available stream
      else if (manifest.streams.isNotEmpty) {
        streamUrl = manifest.streams.first.url.toString();
      }

      if (streamUrl == null) {
        throw "No downloadable stream found.";
      }

      return _buildResponse(video, streamUrl);
    } on VideoUnavailableException {
      throw "Video is unavailable (Private or Removed).";
    } catch (e) {
      throw "Error: ${e.toString().replaceAll("Exception:", "")}";
    }
  }

  /// 4. Build response map
  Map<String, String> _buildResponse(Video video, String streamUrl) {
    return {
      'title': _safeFileName(video.title),
      'url': streamUrl,
      'thumbnail': video.thumbnails.highResUrl,
      'author': video.author,
    };
  }

  /// 5. Clean filename to avoid FileSystemException (Error 36)
  String _safeFileName(String input) {
    return input.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
  }

  /// 6. Dispose resources
  void close() {
    _yt.close();
  }
}