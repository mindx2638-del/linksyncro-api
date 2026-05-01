import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:media_scanner/media_scanner.dart';
import 'package:path_provider/path_provider.dart';

import 'youtube_service.dart';
import 'facebook_service.dart';
import 'instagram_service.dart';

import 'package:photo_manager/photo_manager.dart';
import 'video_gallery_page.dart'; 
import 'video_player_page.dart';  

import 'my_audio_handler.dart';
import 'package:audio_service/audio_service.dart';

import 'dart:isolate';
import 'dart:ui';
import 'package:flutter_downloader/flutter_downloader.dart';

late MyAudioHandler audioHandler;

@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final SendPort? send = IsolateNameServer.lookupPortByName('downloader_send_port');
  send?.send([id, status, progress]);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterDownloader.initialize(
    debug: true, 
    ignoreSsl: true,
  );
  audioHandler = await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.linksyncro.pro.audio',
      androidNotificationChannelName: 'LinkSyncro Playback',
      androidNotificationIcon: 'mipmap/ic_launcher', 
      androidShowNotificationBadge: true,
      androidStopForegroundOnPause: false,
    ),
  );

  runApp(const LinkSyncroApp());
}


class DownloadTask {
  String id;
  String inputUrl;
  String? videoTitle;
  String? thumbnailUrl;
  String? downloadUrl;
  String? savePath;
  double progress;
  String statusText;
  bool isProcessing;
  bool isPaused;
  bool isFinished;


  DownloadTask({
    required this.id,
    required this.inputUrl,
    this.videoTitle,
    this.thumbnailUrl,
    this.downloadUrl,
    this.savePath,
    this.progress = 0,
    this.statusText = "Analyzing...",
    this.isProcessing = true,
    this.isPaused = false,
    this.isFinished = false,
  });
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
        brightness: Brightness.light,
        colorSchemeSeed: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFF0F111A), // Deep Dark
      ),
      themeMode: ThemeMode.system,
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

   final ReceivePort _port = ReceivePort();
   @override
void initState() {
  super.initState();
  _checkPermission();
  IsolateNameServer.removePortNameMapping('downloader_send_port');
  IsolateNameServer.registerPortWithName(_port.sendPort, 'downloader_send_port');
  _port.listen((dynamic data) {
    String id = data[0];
    int status = data[1];
    int progress = data[2];

    setState(() {
      final task = _downloadTasks.firstWhere(
        (t) => t.id == id, 
        orElse: () => DownloadTask(id: "", inputUrl: "")
      );
      
      if (task.id.isNotEmpty) {
        if (progress != -1) {
          task.progress = progress / 100;
        }
        if (status == 3) { // Complete
          task.isFinished = true;
          task.isProcessing = false;
          task.statusText = "Saved to Gallery";
        } else if (status == 4) { // Failed
          task.statusText = "Download Failed";
          task.isProcessing = false;
        } else if (status == 2) { // Running
          task.statusText = "Downloading...";
        } else if (status == 0) { // Enqueued/Waiting
          task.statusText = "Waiting...";
        }
      }
    });
  });

  FlutterDownloader.registerCallback(downloadCallback);
}


  Future<void> _checkPermission() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }
  final TextEditingController _urlController = TextEditingController();
  final List<DownloadTask> _downloadTasks = [];
  final YouTubeService _ytService = YouTubeService();
  final FacebookService _fbService = FacebookService();
  final InstagramService _igService = InstagramService();
  
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null) {
      setState(() => _urlController.text = data!.text!.trim());
    }
  }

  Future<bool> _handlePermissions() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.videos.request().isGranted ||
        await Permission.storage.request().isGranted ||
        await Permission.manageExternalStorage.request().isGranted) {
      return true;
    }
    return false;
  }

  void _addNewDownload() async {
    final input = _urlController.text.trim();
    if (input.isEmpty) {
      _showToast("Please paste a link first", isError: true);
      return;
    }
    if (!await _handlePermissions()) {
      _showToast("Storage permission denied!", isError: true);
      return;
    }

    final task = DownloadTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      inputUrl: input,
    );

    setState(() {
      _downloadTasks.insert(0, task);
      _urlController.clear();
    });

    _startDownloadProcess(task);
  }

  Future<void> _startDownloadProcess(DownloadTask task) async {
  try {
    final result = await _resolveLink(task.inputUrl);
    setState(() {
      task.downloadUrl = result['url'];
      task.videoTitle = result['title'] ?? "Video_${task.id}";
      task.thumbnailUrl = result['thumbnail'];
    });

    if (task.downloadUrl == null) throw "Invalid response from server";
    final directory = await getExternalStorageDirectory();
    if (directory == null) throw "Storage access denied";
    final folder = Directory("${directory.path}/LinkSyncro");
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    String cleanName = task.videoTitle!.replaceAll(RegExp(r'[<>:"/\\|?*]'), '').trim();
    if (cleanName.length > 50) {
      cleanName = cleanName.substring(0, 50).trim();
    }
    if (cleanName.isEmpty) cleanName = "Video_${task.id}";
    task.savePath = "${folder.path}/$cleanName.mp4";
    await _executeDownload(task);   
  } catch (e) {
    _handleTaskError(task, e);
  }
}

Future<void> _executeDownload(DownloadTask task) async {
  try {
    final taskId = await FlutterDownloader.enqueue(
      url: task.downloadUrl!,
      savedDir: task.savePath!.substring(0, task.savePath!.lastIndexOf('/')), 
      fileName: task.savePath!.split('/').last, 
      showNotification: true,
      openFileFromNotification: true,
      saveInPublicStorage: true,
    );

    if (taskId != null) {
      setState(() {
        task.id = taskId;
        task.statusText = "Downloading...";
      });
    }
  } catch (e) {
    debugPrint("Execute Error: $e");
    _handleTaskError(task, "Download request failed");
  }
}

  Future<Map<String, dynamic>> _resolveLink(String input) async {
  if (_ytService.isYouTubeLink(input)) return await _ytService.getVideoDetails(input);
  if (_fbService.isFacebookLink(input)) return await _fbService.getVideoDetails(input);
  if (_igService.isInstagramLink(input)) return await _igService.getVideoDetails(input);

  final List<String> customApiUrls = [
    "https://linksyncro-api-production.up.railway.app/exec",
    "https://linksyncro-api-1.onrender.com/exec",
  ];

  String? lastError;

  for (String apiUrl in customApiUrls) {
    try {
      final uri = Uri.parse("$apiUrl?url=${Uri.encodeComponent(input)}");
      final response = await http.get(uri).timeout(const Duration(seconds: 35));

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      lastError = e.toString();
      debugPrint("Custom API Attempt Failed: $e");
      continue; 
    }
  }

  try {
    const String googleScriptUrl = "https://script.google.com/macros/s/AKfycbxsns846mdhcNrberwkvdB12yJ58pVg3yE6b4tbvp6rOWPxdjYvN7xeEDbIfID0_CrqJg/exec";
    final uri = Uri.parse("$googleScriptUrl?url=${Uri.encodeComponent(input)}");
    
    final response = await http.get(uri).timeout(const Duration(seconds: 45));
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw "Status: ${response.statusCode}";
    }
  } catch (e) {
   throw "Servers are busy. Please try again later. ($lastError)";
  }
}

  void _togglePauseResume(DownloadTask task) {
    if (task.isPaused) {
      FlutterDownloader.resume(taskId: task.id);
      setState(() => task.isPaused = false);
    } else {
      FlutterDownloader.pause(taskId: task.id);
      setState(() => task.isPaused = true);
    }
  }

  void _cancelDownload(DownloadTask task) {
    FlutterDownloader.cancel(taskId: task.id);
    setState(() => _downloadTasks.remove(task));
    _showToast("Download Cancelled");
  }

  void _handleTaskError(DownloadTask task, dynamic e) {
    String displayMsg = "Error occurred";
    if (e.toString().contains("FileSystemException")) {
      displayMsg = "Storage Error: Name too long";
    } else if (e.toString().contains("429")) {
      displayMsg = "YouTube Limit: Try in 5 min";
    }
    setState(() {
      task.isProcessing = false;
      task.isPaused = false;
      task.statusText = displayMsg;
    });
    _showToast(displayMsg, isError: true);
  }

  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: isError ? Colors.redAccent : Colors.indigo,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

 @override
Widget build(BuildContext context) {
  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  final Color bgColor = isDark ? const Color(0xFF0F111A) : const Color(0xFFF8F9FA);

  return Scaffold(
    backgroundColor: bgColor,
    drawer: Drawer(
      backgroundColor: isDark ? const Color(0xFF1C1F2E) : Colors.white,
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Colors.indigo),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.sync_rounded, color: Colors.white, size: 50),
                  const SizedBox(height: 10),
                  const Text("LINKSYNCRO PRO", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                ],
              ),
            ),
          ),
          ListTile(leading: const Icon(Icons.settings_outlined, color: Colors.indigo), title: const Text("Settings"), onTap: () => Navigator.pop(context)),
          ListTile(leading: const Icon(Icons.history_rounded, color: Colors.indigo), title: const Text("Download History"), onTap: () => Navigator.pop(context)),
          const Divider(),
          ListTile(leading: const Icon(Icons.info_outline, color: Colors.indigo), title: const Text("About"), onTap: () => Navigator.pop(context)),
        ],
      ),
    ),

    // ২. AppBar
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.indigo),
      title: Text("LINKSYNCRO", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, color: isDark ? Colors.white : Colors.indigo)),
      actions: [
        IconButton(
          icon: Icon(Icons.delete_sweep_rounded, color: isDark ? Colors.white : Colors.indigo),
          tooltip: "Clear Completed",
          onPressed: () => setState(() => _downloadTasks.retainWhere((t) => !t.isFinished)),
        ),
        IconButton(
          icon: Icon(Icons.video_library_rounded, color: isDark ? Colors.white : Colors.indigo),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const VideoGalleryPage())),
        ),
        const SizedBox(width: 10),
      ],
    ),

    body: Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1F2E) : Colors.white,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
          ),
          child: Column(
            children: [
              TextField(
                controller: _urlController,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
                  hintText: "Paste video link here...",
                  prefixIcon: const Icon(Icons.link_rounded, color: Colors.indigo),
                  suffixIcon: IconButton(icon: const Icon(Icons.content_paste_rounded, color: Colors.indigo), onPressed: _pasteFromClipboard),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 0,
                  ),
                  onPressed: _addNewDownload,
                  child: const Text("DOWNLOAD NOW", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _downloadTasks.isEmpty 
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_download_outlined, size: 80, color: Colors.indigo.withOpacity(0.2)),
                    const SizedBox(height: 16),
                    Text("No downloads yet", style: TextStyle(fontSize: 16, color: isDark ? Colors.white38 : Colors.grey)),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                physics: const BouncingScrollPhysics(),
                itemCount: _downloadTasks.length,
                itemBuilder: (context, index) {
                  final task = _downloadTasks[index];
                  return Dismissible(
                    key: Key(task.id),
                    background: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(24)),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (direction) => setState(() => _downloadTasks.removeAt(index)),
                    child: _buildDownloadCard(task, isDark),
                  );
                },
              ),
        ),
      ],
    ),
  );
}

 Widget _buildDownloadCard(DownloadTask task, bool isDark) {
  final double safeProgress = (task.progress < 0) ? 0.0 : task.progress;
  final String displayProgress = (task.progress < 0) ? "0%" : "${(task.progress * 100).toStringAsFixed(0)}%";

  return Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF1C1F2E) : Colors.white,
      borderRadius: BorderRadius.circular(24),
      boxShadow: isDark ? [] : [
        BoxShadow(
          color: Colors.black.withOpacity(0.03),
          blurRadius: 15,
          offset: const Offset(0, 8),
        )
      ],
    ),
    child: Column(
      children: [
        Row(
          children: [
            Container(
              width: 90,
              height: 55,
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: task.thumbnailUrl != null
                    ? Image.network(task.thumbnailUrl!, fit: BoxFit.cover)
                    : Icon(Icons.play_circle_fill, color: isDark ? Colors.white24 : Colors.black26),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.videoTitle ?? "Processing URL...",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    task.statusText,
                    style: TextStyle(
                      fontSize: 12,
                      color: task.statusText.contains("Error") ? Colors.redAccent : (isDark ? Colors.white60 : Colors.black54),
                    ),
                  ),
                ],
              ),
            ),
            if (!task.isFinished) ...[
              IconButton(
                icon: Icon(task.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                onPressed: () => _togglePauseResume(task),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
                onPressed: () => _cancelDownload(task),
                visualDensity: VisualDensity.compact,
              ),
            ] else ...[
              const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
            ],
          ],
        ),
        const SizedBox(height: 18),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: safeProgress,
            minHeight: 6,
            backgroundColor: isDark ? Colors.white10 : Colors.grey[200],
            valueColor: AlwaysStoppedAnimation(task.isFinished ? Colors.greenAccent : Colors.indigo),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              displayProgress,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.black54),
            ),
            if (task.isFinished)
              const Text("COMPLETED", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
          ],
        ),
      ],
    ),
  );
}
}