import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  bool _isLoading = false;
  String? _downloadUrl;
  String? _videoTitle;

  final String _apiUrl = "https://linksyncro-api-1.onrender.com/get_video";

  // 📋 Paste
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data != null) {
      setState(() {
        _urlController.text = data.text ?? "";
      });
    }
  }

  // 🚀 PROCESS LINK (ALL LINKS VIA API)
  Future<void> _processLink() async {
    final input = _urlController.text.trim();

    if (input.isEmpty) {
      _showToast("Paste a link first", true);
      return;
    }

    setState(() {
      _isLoading = true;
      _downloadUrl = null;
      _videoTitle = null;
    });

    try {
      final encodedUrl = Uri.encodeComponent(input);
      final response =
          await http.get(Uri.parse("$_apiUrl?url=$encodedUrl"));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'success') {
          setState(() {
            _videoTitle = data['title'];
            _downloadUrl = data['url'];
          });

          _showToast("Ready to download!", false);
        } else {
          _showToast("Video not supported or blocked", true);
        }
      } else {
        _showToast("Server busy, try again", true);
      }
    } catch (e) {
      _showToast("Error fetching video", true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 🌐 DOWNLOAD
  Future<void> _downloadVideo() async {
    if (_downloadUrl == null) return;

    final uri = Uri.parse(_downloadUrl!);

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showToast("Failed to open link", true);
    }
  }

  // 🔔 TOAST
  void _showToast(String msg, bool isError) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.indigo,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("LINKSYNCRO PRO"),
        centerTitle: true,
      ),
      body: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [Colors.black, Colors.indigo.shade900]
                : [Colors.indigo.shade50, Colors.white],
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 30),

            const Icon(Icons.bolt, size: 80, color: Colors.indigo),

            const SizedBox(height: 10),
            const Text(
              "Video Downloader",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 30),

            // 🔗 INPUT
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                hintText: "Paste link...",
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

            // 🚀 BUTTON
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _processLink,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("ANALYZE LINK"),
              ),
            ),

            const SizedBox(height: 30),

            // ✅ RESULT
            if (_videoTitle != null)
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    children: [
                      const Icon(Icons.check_circle,
                          color: Colors.green, size: 40),

                      const SizedBox(height: 10),

                      Text(
                        _videoTitle!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold),
                      ),

                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _downloadVideo,
                          icon: const Icon(Icons.download),
                          label: const Text("DOWNLOAD"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}