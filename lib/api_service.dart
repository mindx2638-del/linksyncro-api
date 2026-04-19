import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // আপনার রেন্ডার সার্ভারের ইউআরএল
  static const String _baseUrl = "https://linksyncro-api-1.onrender.com/get_media";
  static const String _apiKey = "demo_key_123"; 

  Future<Map<String, dynamic>> fetchMediaDetails(String url) async {
    final uri = Uri.parse("$_baseUrl?url=${Uri.encodeComponent(url)}");
    
    final response = await http.get(
      uri, 
      headers: {"x-api-key": _apiKey}
    ).timeout(const Duration(seconds: 45));

    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw "Server Error: ${response.statusCode}";
    }
  }
}