import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart'; 
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

void main() {
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
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
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
  final yt = YoutubeExplode(); 
  bool _isLoading = false;
  String? _downloadUrl;
  String? _videoTitle;

  final String _apiUrl = "https://linksyncro-api-1.onrender.com/get_video";

  Future<void> _pasteFromClipboard() async {
    ClipboardData? data = await Clipboard.getData('text/plain');
    if (data != null) {
      setState(() {
        _urlController.text = data.text ?? "";
      });
    }
  }

  Future<void> _processLink() async {
    String input = _urlController.text.trim();
    if (input.isEmpty) {
      _showCustomToast("Please paste a link first", isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
      _downloadUrl = null;
      _videoTitle = null;
    });

    try {
      // ইউটিউব লিঙ্কের জন্য সরাসরি প্রসেসিং
      if (input.contains("youtube.com") || input.contains("youtu.be")) {
        // ভিডিও আইডি বের করা (যেকোনো ইউটিউব লিঙ্কের জন্য কাজ করবে)
        var videoId = VideoId.parseVideoId(input); 
        
        var video = await yt.videos.get(videoId);
        var manifest = await yt.videos.streamsClient.getManifest(videoId);
        
        // সেরা কোয়ালিটির এমপি৪ লিঙ্ক নেওয়া
        var streamInfo = manifest.muxed.withHighestBitrate();

        setState(() {
          _videoTitle = video.title;
          _downloadUrl = streamInfo.url.toString();
        });
        _showCustomToast("YouTube Video Ready!", isError: false);
      } 
      // টিকটক বা অন্যান্য লিঙ্কের জন্য রেন্ডার সার্ভার
      else {
        final response = await http.get(Uri.parse("$_apiUrl?url=$input"));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['status'] == 'success') {
            setState(() {
              _videoTitle = data['title'];
              _downloadUrl = data['url'];
            });
            _showCustomToast("Ready to download!", isError: false);
          } else {
            _showCustomToast("Server Blocked (403)", isError: true);
          }
        } else {
          _showCustomToast("Server busy, try again in 10s", isError: true);
        }
      }
    } catch (e) {
      _showCustomToast("Could not fetch video info", isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showCustomToast(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: isError ? Colors.redAccent : Colors.indigo,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(15),
      ),
    );
  }

  Future<void> _downloadVideo() async {
    if (_downloadUrl != null) {
      final Uri uri = Uri.parse(_downloadUrl!);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _showCustomToast("Could not open browser", isError: true);
      }
    }
  }

  @override
  void dispose() {
    yt.close(); 
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("LINKSYNCRO PRO", 
          style: TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.w900, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: Theme.of(context).brightness == Brightness.light 
              ? [Colors.indigo.shade50, Colors.white]
              : [Colors.black, Colors.indigo.shade900.withOpacity(0.3)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 40),
                Hero(
                  tag: 'logo',
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.indigo.withOpacity(0.1),
                    ),
                    child: const Icon(Icons.bolt_rounded, size: 100, color: Colors.indigo),
                  ),
                ),
                const SizedBox(height: 20),
                const Text("Pro Video Downloader", 
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const Text("Direct Support for All YouTube Links", 
                  style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 40),

                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))
                    ],
                  ),
                  child: TextField(
                    controller: _urlController,
                    decoration: InputDecoration(
                      hintText: "Paste YouTube/TikTok link...",
                      prefixIcon: const Icon(Icons.link_rounded),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.paste_rounded, color: Colors.indigo),
                        onPressed: _pasteFromClipboard,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).cardColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _processLink,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white) 
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.auto_awesome),
                            SizedBox(width: 10),
                            Text("ANALYZE LINK", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                  ),
                ),

                const SizedBox(height: 30),

                if (_videoTitle != null)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(25),
                      gradient: const LinearGradient(colors: [Colors.indigo, Colors.cyan]),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(23),
                        color: Theme.of(context).cardColor,
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green, size: 40),
                          const SizedBox(height: 15),
                          Text(
                            _videoTitle!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 25),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _downloadVideo,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.green.shade600,
                                padding: const EdgeInsets.all(18),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              ),
                              icon: const Icon(Icons.download_rounded),
                              label: const Text("DOWNLOAD NOW", style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}