import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:media_scanner/media_scanner.dart';

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
        brightness: Brightness.dark,
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
  String? _thumbnailUrl;

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

      final url = result['url'];
      final title = result['title'];
      final thumb = result['thumbnail'];

      if (url == null || title == null) {
        throw "Invalid response";
      }

      setState(() {
        _videoTitle = title.toString();
        _thumbnailUrl = thumb?.toString();
      });

      // 🔥 NEW: check quality system
      if (result['formats'] != null) {
        _showQualityDialog(result['formats'], title.toString());
      } else {
        await _downloadFile(url.toString(), "$title.mp4");
      }
    } catch (e) {
      _handleError(e);
    }
  }

  Future<Map<String, dynamic>> _resolveLink(String input) async {
    if (_ytService.isYouTubeLink(input)) {
      return await _ytService.getVideoDetails(input);
    }
    if (_fbService.isFacebookLink(input)) {
      return await _fbService.getVideoDetails(input);
    }
    if (_igService.isInstagramLink(input)) {
      return await _igService.getVideoDetails(input);
    }

    final uri = Uri.parse(
      "https://linksyncro-api-1.onrender.com/get_video?url=${Uri.encodeComponent(input)}",
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 20));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      return {
        'url': data['url'],
        'title': data['title'] ?? "External Video",
        'thumbnail': data['thumbnail'],

        // 🔥 optional quality list (if backend supports)
        'formats': data['formats'],
      };
    }

    throw "Unsupported link";
  }

  // 🔥 QUALITY PICKER (NEW)
  void _showQualityDialog(List formats, String title) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      builder: (_) {
        return ListView.builder(
          itemCount: formats.length,
          itemBuilder: (context, index) {
            final f = formats[index];

            return ListTile(
              leading: const Icon(Icons.video_file, color: Colors.indigo),
              title: Text("${f['quality'] ?? 'Unknown'}"),
              subtitle: Text(f['has_audio'] == true ? "With Audio" : "Video only"),
              onTap: () {
                Navigator.pop(context);
                _downloadFileFromFormat(f['url'], title);
              },
            );
          },
        );
      },
    );
  }

  Future<void> _downloadFileFromFormat(String url, String title) async {
    await _downloadFile(url, "$title.mp4");
  }

  Future<void> _downloadFile(String url, String fileName) async {
    try {
      setState(() => _statusText = "Preparing...");

      const root = "/storage/emulated/0";
      final folder = Directory("$root/LinkSyncro");

      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }

      final safeName = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final savePath = "${folder.path}/$safeName";

      await _dio.download(
        url,
        savePath,
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
    } catch (e) {
      _handleError(e);
    }
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

  void _handleError(dynamic e) {
    setState(() => _isProcessing = false);
    _showToast("Error: $e", isError: true);
  }

  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.indigo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Text(
                "LINKSYNCRO PRO",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 30),

              TextField(
                controller: _urlController,
                decoration: InputDecoration(
                  hintText: "Paste link here...",
                  prefixIcon: const Icon(Icons.link),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.paste),
                    onPressed: _pasteFromClipboard,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: _isProcessing ? null : _startProcess,
                child: const Text("DOWNLOAD"),
              ),

              const SizedBox(height: 30),

              if (_isProcessing || _downloadProgress > 0)
                Column(
                  children: [
                    LinearProgressIndicator(value: _downloadProgress),
                    const SizedBox(height: 10),
                    Text(
                      _statusText,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}