import 'dart:isolate';
import 'dart:ui';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

// আপনার কাস্টম সার্ভিসগুলো ইমপোর্ট করে রাখবেন
// import 'youtube_service.dart'; ...

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Flutter Downloader ইনিশিয়ালাইজেশন
  await FlutterDownloader.initialize(debug: true, ignoreSsl: true);

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
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blueAccent,
        fontFamily: 'Roboto',
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
  final ReceivePort _port = ReceivePort();
  
  String? _taskId;
  DownloadTaskStatus _status = DownloadTaskStatus.undefined;
  int _progress = 0;
  String _statusMessage = "Ready to download";
  bool _isAnalyzing = false;

  @override
  void initState() {
    super.initState();
    _bindBackgroundIsolate();
    FlutterDownloader.registerCallback(downloadCallback);
  }

  @override
  void dispose() {
    _unbindBackgroundIsolate();
    super.dispose();
  }

  // ব্যাকগ্রাউন্ড ডাউনলোড লিসেনার
  void _bindBackgroundIsolate() {
    bool isSuccess = IsolateNameServer.registerPortWithName(
        _port.sendPort, 'downloader_send_port');
    if (!isSuccess) {
      _unbindBackgroundIsolate();
      _bindBackgroundIsolate();
      return;
    }
    _port.listen((dynamic data) {
      setState(() {
        _status = DownloadTaskStatus.fromInt(data[1]);
        _progress = data[2];
      });
    });
  }

  void _unbindBackgroundIsolate() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
  }

  @pragma('vm:entry-point')
  static void downloadCallback(String id, int status, int progress) {
    final SendPort? send = IsolateNameServer.lookupPortByName('downloader_send_port');
    send?.send([id, status, progress]);
  }

  Future<void> _startDownload() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    // পারমিশন চেক
    var status = await Permission.storage.request();
    if (Platform.isAndroid && await Permission.manageExternalStorage.request().isDenied) {
      return;
    }

    setState(() => _isAnalyzing = true);

    // এখানে আপনার _resolveLink ফাংশন কল করবেন যা URL থেকে সরাসরি ভিডিও লিঙ্ক বের করবে
    // উদাহরণের জন্য আমি সরাসরি URL ব্যবহার করছি
    try {
      final baseStorage = await getExternalStorageDirectory();
      final savedDir = Directory("${baseStorage!.path}/LinkSyncro");
      if (!await savedDir.exists()) await savedDir.create(recursive: true);

      final taskId = await FlutterDownloader.enqueue(
        url: url, // এখানে ভিডিওর ডিরেক্ট লিঙ্ক দিতে হবে
        savedDir: savedDir.path,
        fileName: "Video_${DateTime.now().millisecondsSinceEpoch}.mp4",
        showNotification: true, 
        openFileFromNotification: true,
        saveInPublicStorage: true,
      );

      setState(() {
        _taskId = taskId;
        _isAnalyzing = false;
      });
    } catch (e) {
      setState(() => _isAnalyzing = false);
      _showSnackBar("Error: $e");
    }
  }

  void _pauseDownload() async => await FlutterDownloader.pause(taskId: _taskId!);
  void _resumeDownload() async => await FlutterDownloader.resume(taskId: _taskId!);
  void _cancelDownload() async => await FlutterDownloader.cancel(taskId: _taskId!);

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [const Color(0xFF0F172A), Colors.blueGrey.shade900],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 50),
                const Text("LinkSyncro", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                const Text("Fast & Secure Downloader", style: TextStyle(color: Colors.blueAccent, fontSize: 16)),
                const SizedBox(height: 40),
                
                // Input Section
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: TextField(
                    controller: _urlController,
                    decoration: InputDecoration(
                      hintText: "Paste video link here...",
                      border: InputBorder.none,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.paste, color: Colors.blueAccent),
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data?.text != null) _urlController.text = data!.text!;
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _isAnalyzing ? null : _startDownload,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isAnalyzing 
                      ? const CircularProgressIndicator(color: Colors.white) 
                      : const Text("DOWNLOAD NOW", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),

                const SizedBox(height: 40),

                // Download Card
                if (_taskId != null) 
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20)],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 50, height: 50,
                            decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.movie_filter, color: Colors.blueAccent),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_status == DownloadTaskStatus.complete ? "Download Finished" : "Downloading...", 
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text(_urlController.text, maxLines: 1, overflow: TextOverflow.ellipsis, 
                                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      LinearProgressIndicator(
                        value: _progress / 100,
                        backgroundColor: Colors.white.withOpacity(0.1),
                        color: Colors.blueAccent,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("$_progress%", style: const TextStyle(fontWeight: FontWeight.bold)),
                          Row(
                            children: [
                              if (_status == DownloadTaskStatus.running)
                                _ActionButton(icon: Icons.pause, color: Colors.orange, onTap: _pauseDownload),
                              if (_status == DownloadTaskStatus.paused)
                                _ActionButton(icon: Icons.play_arrow, color: Colors.green, onTap: _resumeDownload),
                              const SizedBox(width: 10),
                              _ActionButton(icon: Icons.close, color: Colors.redAccent, onTap: _cancelDownload),
                            ],
                          )
                        ],
                      )
                    ],
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

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}