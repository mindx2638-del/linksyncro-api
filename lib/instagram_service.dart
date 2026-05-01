import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

class InstagramService {
  // ১. একাধিক রেন্ডার সার্ভার লিঙ্কের লিস্ট
  final List<String> _apiUrls = [
    
    "https://linksyncro-api-b08a.onrender.com/get_media",
    "https://linksyncro-api-f1k4.onrender.com/get_media",
  
  ];
  
  // API Key (Python Server এর VALID_API_KEYS এ থাকা কী)
  static const String _apiKey = "demo_key_123"; 

  // লিঙ্কটি ইনস্টাগ্রামের কি না তা চেক করা
  bool isInstagramLink(String url) {
    String lowerUrl = url.toLowerCase();
    return lowerUrl.contains("instagram.com");
  }

  // রেন্ডার সার্ভার থেকে ডাটা আনা (Failover Logic সহ)
  Future<Map<String, dynamic>> getVideoDetails(String url) async {
    String targetUrl = url.trim();
    String lastErrorMessage = "Could not retrieve Instagram video.";

    // ২. লুপের মাধ্যমে প্রতিটি সার্ভার ট্রাই করা
    for (int i = 0; i < _apiUrls.length; i++) {
      String currentServerUrl = _apiUrls[i];

      try {
        final uri = Uri.parse("$currentServerUrl?url=${Uri.encodeComponent(targetUrl)}");

        final response = await http.get(
          uri,
          headers: {
            "x-api-key": _apiKey,
            "Accept": "application/json",
          },
        ).timeout(const Duration(seconds: 25)); // প্রতি সার্ভারের জন্য ২৫ সেকেন্ড

        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          
          if (data['status'] == 'success') {
            // ডাটা পাওয়া গেলে সরাসরি রিটার্ন করবে এবং লুপ থেমে যাবে
            return data;
          } else {
            lastErrorMessage = data['message'] ?? "Error on Server ${i + 1}";
          }
        } else if (response.statusCode == 401) {
          lastErrorMessage = "Unauthorized API Key on Server ${i + 1}";
        } else if (response.statusCode == 429) {
          lastErrorMessage = "Rate limit exceeded on Server ${i + 1}";
        } else {
          lastErrorMessage = "Server ${i + 1} Error: ${response.statusCode}";
        }

        print("Instagram: Server ${i + 1} failed, trying next...");

      } catch (e) {
        if (e is TimeoutException) {
          lastErrorMessage = "Server ${i + 1} timed out.";
        } else {
          lastErrorMessage = "Connection error with Server ${i + 1}.";
        }
        print("Instagram Error (Server ${i + 1}): $e");
        // এরর হলেও পরের সার্ভারে চেষ্টা করবে
        continue;
      }
    }

    // সব সার্ভার ফেইল করলে এরর থ্রো করবে
    throw lastErrorMessage;
  }
}