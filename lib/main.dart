import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

void main() {
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
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

  // IMPORTANT: Updated with the correct '-1' suffix from your Render dashboard
  final String _apiUrl = "https://linksyncro-api-1.onrender.com/get_video";

  Future<void> _processLink() async {
    String input = _urlController.text.trim();
    if (input.isEmpty) {
      _showMessage("Please paste a video link", isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
      _downloadUrl = null;
      _videoTitle = null;
    });

    try {
      final response = await http.get(Uri.parse("$_apiUrl?url=$input"));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          setState(() {
            _videoTitle = data['title'];
            _downloadUrl = data['url'];
          });
          _showMessage("Video details fetched successfully!");
        } else {
          _showMessage("Could not find video info", isError: true);
        }
      } else {
        _showMessage("Server is not responding correctly", isError: true);
      }
    } catch (e) {
      _showMessage("Connection error! Server might take 30s to wake up.", isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showMessage(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _downloadVideo() async {
    if (_downloadUrl != null) {
      final Uri uri = Uri.parse(_downloadUrl!);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _showMessage("Could not launch download link", isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("LinkSyncro Pro", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 2,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Icon(Icons.cloud_download_outlined, size: 80, color: Colors.indigo),
            const SizedBox(height: 10),
            const Text("Fast & Reliable Video Downloader", 
              style: TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 30),
            
            // Input Field
            TextField(
              controller: _urlController,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: "Paste YouTube Link Here...",
                prefixIcon: const Icon(Icons.link),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _urlController.clear(),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                filled: true,
                fillColor: Colors.blueGrey.withOpacity(0.05),
              ),
            ),
            const SizedBox(height: 20),

            // Analyze Button
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _processLink,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white) 
                  : const Text("Get Download Info", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),

            const SizedBox(height: 40),

            // Result Card
            if (_videoTitle != null) 
              Card(
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      colors: [Colors.white, Colors.blue.withOpacity(0.05)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.play_circle_fill, size: 50, color: Colors.redAccent),
                      const SizedBox(height: 15),
                      Text(
                        _videoTitle!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 25),
                      ElevatedButton.icon(
                        onPressed: _downloadVideo,
                        icon: const Icon(Icons.download_for_offline),
                        label: const Text("Download Now"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                      ),
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
