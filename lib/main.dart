import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:media_scanner/media_scanner.dart';

// আপনার কাস্টম সার্ভিসগুলো (নিশ্চিত করুন এগুলোতে thumbnail রিটার্ন করে)
import 'youtube_service.dart';
import 'facebook_service.dart';
import 'instagram_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );
  runApp(const LinkSyncroApp());
}

class LinkSyncroApp extends StatelessWidget {
  const LinkSyncroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LinkSyncro Pro',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark, // ছবির মতো লুক পেতে ডার্ক থিম
        colorSchemeSeed: Colors.indigo,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _urlController = TextEditingController();
  final YouTubeService _ytService = YouTubeService();
  final FacebookService _fbService = FacebookService();
  final InstagramService _igService = InstagramService();
  final Dio _dio = Dio();

  bool _isProcessing = false;
  double _downloadProgress = 0;
  String _statusText = "Ready to download";
  String? _videoTitle;
  String? _thumbnailUrl; // থাম্বনেইল স্টোর করার জন্য

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null) {
      setState(() => _urlController.text = data!.text!.trim());
    }
  }

  Future<bool> _handlePermissions() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.manageExternalStorage.isGranted) return true;
    final status = await Permission.manageExternalStorage.request();
    return status.isGranted;
  }

  Future<void> _startProcess() async {
    final input = _urlController.text.trim();
    if (input.isEmpty) {
      _showToast("Please paste a link first", isError: true);
      return;
    }
    if (!await _handlePermissions()) {
      _showToast("Storage permission denied!", isError: true);
      return;
    }

    _resetState("Analyzing link...");

    try {
      final result = await _resolveLink(input);
      
      // API বা সার্ভিস থেকে ডাটা নেওয়া
      final url = result['url'];
      final title = result['title'];
      final thumb = result['thumbnail']; // থাম্বনেইল কী (Key)

      if (url == null || title == null) throw "Invalid response from server";

      setState(() {
        _videoTitle = title.toString();
        _thumbnailUrl = thumb?.toString(); // থাম্বনেইল সেট করা
      });

      await _downloadFile(url.toString(), "${title.toString()}.mp4");
    } catch (e) {
      _handleError(e);
    }
  }

  Future<Map<String, dynamic>> _resolveLink(String input) async {
    // নোট: আপনার সার্ভিসগুলোকেও 'thumbnail' কী রিটার্ন করতে হবে
    if (_ytService.isYouTubeLink(input)) return await _ytService.getVideoDetails(input);
    if (_fbService.isFacebookLink(input)) return await _fbService.getVideoDetails(input);
    if (_igService.isInstagramLink(input)) return await _igService.getVideoDetails(input);

    final uri = Uri.parse("https://linksyncro-api-1.onrender.com/get_video?url=${Uri.encodeComponent(input)}");
    final response = await http.get(uri).timeout(const Duration(seconds: 20));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return {
        'url': data['url'],
        'title': data['title'] ?? "External Video",
        'thumbnail': data['thumbnail'], // API থেকে থাম্বনেইল কালেকশন
      };
    }
    throw "Unsupported or invalid link";
  }

  Future<void> _downloadFile(String url, String fileName) async {
    try {
      setState(() => _statusText = "Preparing...");
      const root = "/storage/emulated/0";
      final folder = Directory("$root/LinkSyncro");
      if (!await folder.exists()) await folder.create(recursive: true);

      final safeName = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
      final savePath = "${folder.path}/$safeName";

      await _dio.download(
        url, savePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            setState(() {
              _downloadProgress = received / total;
              _statusText = "Downloading...";
            });
          }
        },
      );

      await MediaScanner.loadMedia(path: savePath);
      setState(() {
        _isProcessing = false;
        _statusText = "Saved to LinkSyncro";
      });
      _showToast("Download Completed!");
    } catch (e) { _handleError(e); }
  }

  void _handleError(dynamic e) {
    setState(() => _isProcessing = false);
    _showToast("Error: $e", isError: true);
  }

  void _resetState(String status) {
    setState(() {
      _isProcessing = true;
      _downloadProgress = 0;
      _statusText = status;
      _videoTitle = null;
      _thumbnailUrl = null;
    });
  }

  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? Colors.red : Colors.indigo),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E), // ছবির মতো ব্যাকগ্রাউন্ড কালার
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Text("LINKSYNCRO PRO", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 30),
              
              // ইনপুট বক্স
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    hintText: "Paste link here...",
                    prefixIcon: const Icon(Icons.link, color: Colors.indigo),
                    suffixIcon: IconButton(icon: const Icon(Icons.paste), onPressed: _pasteFromClipboard),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(15),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: Colors.indigo,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: _isProcessing ? null : _startProcess,
                child: const Text("DOWNLOAD", style: TextStyle(color: Colors.white)),
              ),

              const SizedBox(height: 40),

              // আপনার দেওয়া ছবির মতো ডাউনলোড কার্ড
              if (_isProcessing || _downloadProgress > 0)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF252545), // কার্ডের ডার্ক কালার
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10)],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // থাম্বনেইল সেকশন (ছবির মতো বাম দিকে)
                          Container(
                            width: 100,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: _thumbnailUrl != null 
                                ? Image.network(_thumbnailUrl!, fit: BoxFit.cover)
                                : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            ),
                          ),
                          const SizedBox(width: 15),
                          // টাইটেল এবং ইউআরএল টেক্সট
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isProcessing ? "Downloading..." : "Completed",
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                Text(
                                  _urlController.text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // প্রগ্রেস বার (ছবির মতো নীল রঙের)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: _downloadProgress,
                          minHeight: 6,
                          backgroundColor: Colors.white.withOpacity(0.1),
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // পার্সেন্টেজ এবং স্ট্যাটাস
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("${(_downloadProgress * 100).toStringAsFixed(0)}%", style: const TextStyle(color: Colors.white70)),
                          Text(_statusText, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}