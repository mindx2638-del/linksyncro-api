import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  // YouTube লিংক চেক করা
  bool isYouTubeLink(String url) {
    return url.contains("youtube.com") || url.contains("youtu.be");
  }

  // ভিডিওর টাইটেল, ডাউনলোড ইউআরএল এবং থাম্বনেইল গেট করা
  Future<Map<String, String>> getVideoDetails(String url) async {
    try {
      String? videoId;
      
      if (url.contains("/shorts/")) {
        videoId = url.split("/shorts/")[1].split("?")[0].trim();
      } else {
        videoId = VideoId.parseVideoId(url);
      }

      final video = await _yt.videos.get(videoId);
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      
      // অডিও + ভিডিও সহ সর্বোচ্চ কোয়ালিটি
      final streamInfo = manifest.muxed.withHighestBitrate();

      return {
        'title': video.title.replaceAll(RegExp(r'[^\w\s]+'), ''),
        'url': streamInfo.url.toString(),
        'thumbnail': video.thumbnails.highResUrl, // থাম্বনেইল লজিক
      };
    } catch (e) {
      throw "YouTube error: $e";
    }
  }

  void close() {
    _yt.close();
  }
}