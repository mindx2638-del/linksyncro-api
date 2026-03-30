import 'dart:convert';
import 'package:http/http.dart' as http;

class InstagramService {
  // ১. লিঙ্কটি ইনস্টাগ্রামের কি না তা চেক করা
  bool isInstagramLink(String url) {
    return url.contains("instagram.com/reels/") || 
           url.contains("instagram.com/p/") || 
           url.contains("instagram.com/tv/");
  }

  // ২. ভিডিওর ডিটেইলস (URL, Title, Thumbnail) আনা
  Future<Map<String, dynamic>> getVideoDetails(String url) async {
    try {
      // আমরা এখানে একটি পাবলিক API ব্যবহার করছি (উদাহরণস্বরূপ)
      // নোট: ইনস্টাগ্রামের অফিসিয়াল কোনো ডিরেক্ট ভিডিও ডাউনলোডার API নেই। 
      // নিচের API টি কাজ না করলে আপনার ব্যবহৃত গুগল স্ক্রিপ্ট প্রক্সি (Proxy) অটোমেটিক কাজ করবে।
      
      final String cleanUrl = url.split('?').first; // ট্র্যাকিং প্যারামিটার সরানো
      final response = await http.get(
        Uri.parse("https://api.snapinsta.app/api/video?url=$cleanUrl"),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // আপনার HomeScreen-এর প্রত্যাশিত ফরম্যাটে ডাটা রিটার্ন করা
        return {
          'url': data['download_url'], // ভিডিওর সরাসরি ডাউনলোড লিঙ্ক
          'title': "Instagram_Video_${DateTime.now().millisecondsSinceEpoch}",
          'thumbnail': data['thumbnail_url'] ?? "",
        };
      } else {
        throw "Failed to fetch Instagram video";
      }
    } catch (e) {
      // যদি এই সার্ভিস ফেইল করে, তবে আপনার মেইন কোডের গুগল স্ক্রিপ্ট প্রক্সি রান করবে
      rethrow; 
    }
  }
}