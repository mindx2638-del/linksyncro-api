import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// 1. Validate if the URL is a YouTube link
  bool isYouTubeLink(String url) {
    if (url.isEmpty) return false;

    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    return uri.host.contains('youtube.com') ||
        uri.host.contains('youtu.be');
  }

  /// 2. Extract Video ID from different YouTube URL formats
  String? _extractVideoId(String url) {
    try {
      final uri = Uri.parse(url);

      // youtu.be/<id>
      if (uri.host.contains('youtu.be')) {
        return uri.pathSegments.isNotEmpty
            ? uri.pathSegments.first
            : null;
      }

      // youtube.com/watch?v=<id>
      if (uri.queryParameters.containsKey('v')) {
        return uri.queryParameters['v'];
      }

      // youtube.com/shorts/<id>
      if (uri.pathSegments.contains('shorts')) {
        return uri.pathSegments.last;
      }

      // youtube.com/live/<id>
      if (uri.pathSegments.contains('live')) {
        return uri.pathSegments.last;
      }

      // youtube.com/embed/<id>
      if (uri.pathSegments.contains('embed')) {
        return uri.pathSegments.last;
      }

      // Fallback regex (final safety check)
      final RegExp regExp = RegExp(r'([a-zA-Z0-9_-]{11})');
      final match = regExp.firstMatch(url);
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }

  /// 3. Get video details and download URL (সংশোধিত: ৪কে ও কোয়ালিটি লজিকসহ)
  Future<Map<String, String>> getVideoDetails(String url, {String quality = "1080"}) async {
    try {
      final videoId = _extractVideoId(url.trim());

      if (videoId == null) {
        throw "❌ Invalid video ID. Please check the URL.";
      }

      final video = await _yt.videos.get(videoId);

      /// Check for live/upcoming videos (তোমার অরিজিনাল লজিক)
      if (video.duration == null || video.duration!.inSeconds == 0) {
        throw "⚠️ Live or upcoming videos cannot be downloaded.";
      }

      final manifest = await _yt.videos.streamsClient.getManifest(videoId);

      String? streamUrl;

      // --- নতুন লজিক: ইউজার ৪কে বা ১০৮০পি সিলেক্ট করলে নির্দিষ্ট স্ট্রিম খুঁজবে ---
      if (quality == "2160") {
        // ৪কে (4K) এর জন্য প্রথমে videoOnly চেক করা হবে
        streamUrl = manifest.videoOnly.where((s) => s.videoQuality.name.contains('2160')).firstOrNull?.url.toString() ?? 
                    manifest.videoOnly.withHighestBitrate().url.toString();
      } else if (quality == "1080") {
        // ১০৮০পি (Full HD) এর জন্য muxed অথবা videoOnly চেক করা হবে
        streamUrl = manifest.muxed.where((s) => s.videoQuality.name.contains('1080')).firstOrNull?.url.toString() ??
                    manifest.videoOnly.where((s) => s.videoQuality.name.contains('1080')).firstOrNull?.url.toString() ??
                    manifest.muxed.withHighestBitrate().url.toString();
      } 
      // --- তোমার অরিজিনাল Priority ১, ২, ৩ লজিক (যা আগে ছিল) ---
      else {
        /// Priority 1: muxed (audio + video)
        if (manifest.muxed.isNotEmpty) {
          streamUrl = manifest.muxed.withHighestBitrate().url.toString();
        }
        /// Priority 2: video-only (higher quality)
        else if (manifest.videoOnly.isNotEmpty) {
          streamUrl = manifest.videoOnly.withHighestBitrate().url.toString();
        }
        /// Priority 3: fallback stream
        else if (manifest.streams.isNotEmpty) {
          streamUrl = manifest.streams.first.url.toString();
        }
      }

      if (streamUrl == null) {
        throw "❌ No downloadable stream found.";
      }

      return _buildResponse(video, streamUrl);
    } on VideoUnavailableException {
      throw "❌ Video is unavailable (Private or Removed).";
    } catch (e) {
      throw "❌ Error: ${e.toString()}";
    }
  }


  /// 4. Build response map
  Map<String, String> _buildResponse(
      Video video, String streamUrl) {
    return {
      'title': _safeFileName(video.title),
      'url': streamUrl,
      'thumbnail': video.thumbnails.highResUrl,
      'author': video.author,
    };
  }

  /// 5. Make filename safe for storage
  String _safeFileName(String input) {
    return input.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  /// 6. Dispose resources
  void close() {
    _yt.close();
  }
}