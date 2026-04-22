import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:media_scanner/media_scanner.dart';

// আপনার লোকাল সার্ভিস ফাইলগুলো নিশ্চিত করুন প্রোজেক্টে আছে
import 'youtube_service.dart';
import 'facebook_service.dart';
import 'instagram_service.dart';

import 'package:photo_manager/photo_manager.dart';
import 'video_gallery_page.dart'; // আপনার তৈরি করা ফাইল
import 'video_player_page.dart';  // আপনার তৈরি করা ফাইল

import 'my_audio_handler.dart';
import 'package:audio_service/audio_service.dart';
late MyAudioHandler audioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  audioHandler = await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.linksyncro.pro.audio',
      androidNotificationChannelName: 'LinkSyncro Playback',
      androidNotificationIcon: 'mipmap/ic_launcher', 
      androidShowNotificationBadge: true,
      androidStopForegroundOnPause: false, // এটি পজ করলে নোটিফিকেশন রাখবে
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
  List<dynamic>? availableFormats;
  double progress;
  String statusText;
  bool isProcessing;
  bool isPaused;
  bool isFinished;
  CancelToken cancelToken;

  DownloadTask({
    required this.id,
    required this.inputUrl,
    this.videoTitle,
    this.thumbnailUrl,
    this.downloadUrl,
    this.savePath,
    this.availableFormats,
    this.progress = 0,
    this.statusText = "Analyzing...",
    this.isProcessing = true,
    this.isPaused = false,
    this.isFinished = false,
  }) : cancelToken = CancelToken();
}

class LinkSyncroApp extends StatelessWidget {
  const LinkSyncroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LinkSyncro Pro',
      // ১. লাইট থিম কনফিগারেশন
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      ),
      // ২. ডার্ক থিম কনফিগারেশন (মোবাইলের সিস্টেম অনুযায়ী)
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFF0F111A), // Deep Dark
      ),
      // ৩. সিস্টেম থিম মোড এনাবল করা
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
   @override
  void initState() {
    super.initState();
    _checkPermission();
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
  
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 20),
  ));

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
    // ১. রেজল্ভ লিঙ্ক - ডেটা ফেচ করা
    final result = await _resolveLink(task.inputUrl);
    
    // ২. স্টেট আপডেট এবং ডেটা সেফটি চেক
    setState(() {
      // টাইপ কাস্টিং নিরাপদ করা হলো
      task.availableFormats = (result['formats'] is List) ? result['formats'] : null;
      task.videoTitle = result['title'] ?? "Video_${task.id}";
      task.thumbnailUrl = result['thumbnail'];
      task.downloadUrl = result['url']; 
      task.statusText = "Analyzing Complete"; // স্ট্যাটাস আপডেট করলাম
    });

    // ৩. ফরম্যাট চেক লজিক (নিরাপদ উপায়)
    // ফরম্যাট লিস্ট আছে কি না এবং সেটি খালি কি না তা চেক করছি
    if (task.availableFormats != null && task.availableFormats!.isNotEmpty) {
      _showQualitySelector(task); // কোয়ালিটি সিলেক্টর দেখাও
    } else {
      // যদি ফরম্যাট না থাকে, ডিফল্ট লিঙ্কটি চেক করো
      if (task.downloadUrl == null || task.downloadUrl!.isEmpty) {
        throw "No download link found in response"; // এরর থ্রো করো
      }
      await _proceedToDownload(task); // সরাসরি ডাউনলোড শুরু করো
    }
  } catch (e) {
    // এরর হ্যান্ডলিং আগের মতোই থাকবে
    _handleTaskError(task, e);
  }
}


  Future<Map<String, dynamic>> _resolveLink(String input) async {
    if (_ytService.isYouTubeLink(input)) return await _ytService.getVideoDetails(input);
    if (_fbService.isFacebookLink(input)) return await _fbService.getVideoDetails(input);
    if (_igService.isInstagramLink(input)) return await _igService.getVideoDetails(input);

    const String proxyUrl = "https://script.google.com/macros/s/AKfycbxsns846mdhcNrberwkvdB12yJ58pVg3yE6b4tbvp6rOWPxdjYvN7xeEDbIfID0_CrqJg/exec";
    final uri = Uri.parse("$proxyUrl?url=${Uri.encodeComponent(input)}");

    final response = await http.get(uri).timeout(const Duration(seconds: 45));
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    }
    throw "Proxy server failed to respond";
  }

  Future<void> _executeDownload(DownloadTask task) async {
    RandomAccessFile? raf;
    try {
      File file = File(task.savePath!);
      int downloadedBytes = 0;
      if (await file.exists()) {
        downloadedBytes = await file.length();
      }

      setState(() {
        task.isProcessing = true;
        task.isFinished = false;
        task.statusText = task.isPaused ? "Paused" : "Downloading...";
      });

      task.cancelToken = CancelToken();

      Response response = await _dio.get(
        task.downloadUrl!,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() {
              task.progress = (received + downloadedBytes) / (total + downloadedBytes);
            });
          }
        },
        options: Options(
          responseType: ResponseType.stream,
          headers: {"range": "bytes=$downloadedBytes-"},
        ),
        cancelToken: task.cancelToken,
      );

      if (response.statusCode == 416) {
        if (await file.exists()) await file.delete();
        setState(() => task.progress = 0);
        await _executeDownload(task);
        return;
      }

      raf = await file.open(mode: FileMode.append);
      Stream<Uint8List> stream = response.data.stream;
      await for (var chunk in stream) {
        if (task.isPaused) break;
        await raf.writeFrom(chunk);
      }
      await raf.close();

      if (!task.isPaused) {
        await MediaScanner.loadMedia(path: task.savePath!);
        setState(() {
          task.isProcessing = false;
          task.isFinished = true;
          task.progress = 1.0;
          task.statusText = "Saved to Gallery";
        });
      }
    } catch (e) {
      if (raf != null) await raf.close();
      if (e is DioException && CancelToken.isCancel(e)) return;
      _handleTaskError(task, e);
    }
  }

  void _togglePauseResume(DownloadTask task) {
    if (task.isPaused) {
      setState(() => task.isPaused = false);
      _executeDownload(task);
    } else {
      setState(() {
        task.isPaused = true;
        task.statusText = "Paused";
      });
      task.cancelToken.cancel("Paused");
    }
  }

  void _cancelDownload(DownloadTask task) {
    task.cancelToken.cancel("Cancelled");
    File file = File(task.savePath ?? "");
    if (file.existsSync()) file.deleteSync();
    setState(() {
      _downloadTasks.remove(task);
    });
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

  return Scaffold(
    // ১. ড্রয়ার (Drawer) সেকশন - যা বাম পাশ দিয়ে বের হবে
    drawer: Drawer(
      backgroundColor: isDark ? const Color(0xFF1C1F2E) : Colors.white,
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              color: Colors.indigo,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.sync_rounded, color: Colors.white, size: 50),
                  const SizedBox(height: 10),
                  Text(
                    "LINKSYNCRO PRO",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined, color: Colors.indigo),
            title: const Text("Settings"),
            onTap: () {
              // সেটিংস এ ক্লিক করলে যা হবে
              Navigator.pop(context); // ড্রয়ার বন্ধ হবে
            },
          ),
          ListTile(
            leading: const Icon(Icons.history_rounded, color: Colors.indigo),
            title: const Text("Download History"),
            onTap: () => Navigator.pop(context),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.indigo),
            title: const Text("About"),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    ),

    // ২. AppBar সেকশন - যেখানে ড্রয়ার বাটন (৩টি দাগ) থাকবে
    appBar: AppBar(
      backgroundColor: isDark ? const Color(0xFF0F111A) : Colors.white,
      elevation: 0,
      centerTitle: false,
      // leading এ Builder ব্যবহার করা হয়েছে যেন ড্রয়ারটি ঠিকমতো ওপেন হয়
      leading: Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.menu_rounded, color: Colors.indigo, size: 28), // র‍্যাগ র‍্যাগ আইকন
          onPressed: () => Scaffold.of(context).openDrawer(),
          tooltip: "Settings Menu",
        ),
      ),
      title: Text(
        "LINKSYNCRO",
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
          color: isDark ? Colors.white : Colors.indigo[900],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.video_library_rounded, color: Colors.indigo, size: 28),
          tooltip: "গ্যালারি",
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const VideoGalleryPage()),
            );
          },
        ),
        const SizedBox(width: 10),
      ],
    ),

    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              children: [
                const SizedBox(height: 10),
                // লিঙ্ক পেস্ট করার বক্স
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.08) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: isDark ? [] : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: TextField(
                    controller: _urlController,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    decoration: InputDecoration(
                      hintText: "Paste video link here...",
                      hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black38),
                      prefixIcon: const Icon(Icons.link_rounded, color: Colors.indigo),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.content_paste_rounded, color: Colors.indigo),
                        onPressed: _pasteFromClipboard,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // ডাউনলোড বাটন
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 55),
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  onPressed: _addNewDownload,
                  child: const Text(
                    "DOWNLOAD NOW", 
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                  ),
                ),
              ],
            ),
          ),
          // ডাউনলোড লিস্ট
          Expanded(
            child: _downloadTasks.isEmpty 
              ? Center(
                  child: Text(
                    "No downloads yet", 
                    style: TextStyle(color: isDark ? Colors.white30 : Colors.black26)
                  )
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _downloadTasks.length,
                  itemBuilder: (context, index) {
                    return _buildDownloadCard(_downloadTasks[index], isDark);
                  },
                ),
          ),
        ],
      ),
    ),
  );
}


  Widget _buildDownloadCard(DownloadTask task, bool isDark) {
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
              value: task.progress,
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
                "${(task.progress * 100).toStringAsFixed(0)}%",
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

  void _showQualitySelector(DownloadTask task) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
    ),
    builder: (context) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Select Quality", 
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
            ),
            const Divider(),
            ListView.builder(
              shrinkWrap: true,
              itemCount: task.availableFormats!.length,
              itemBuilder: (context, index) {
                final format = task.availableFormats![index];
                // ব্যাকএন্ড থেকে আসা ফরম্যাটেড স্ট্রিং 'quality' ব্যবহার করছি
                final String qualityLabel = format['quality'] ?? "${format['height']}p";
                final int sizeBytes = format['filesize'] ?? 0;
                final String sizeMB = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);

                return ListTile(
                  leading: const Icon(Icons.video_collection_outlined, color: Colors.indigo),
                  title: Text(qualityLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: sizeBytes > 0 ? Text("$sizeMB MB") : null,
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: () {
                    Navigator.pop(context);
                    task.downloadUrl = format['url']; 
                    _proceedToDownload(task); 
                  },
                );
              },
            ),
          ],
        ),
      );
    },
  );
}

Future<void> _proceedToDownload(DownloadTask task) async {
  try {
    const root = "/storage/emulated/0";
    final folder = Directory("$root/Download/LinkSyncro");
    if (!await folder.exists()) await folder.create(recursive: true);

    // আগের সেই ফাইল নেম ক্লিনিং এবং লেন্থ লিমিট (Error 36 Fix)
    String cleanName = task.videoTitle!.replaceAll(RegExp(r'[<>:"/\\|?*]'), '').trim();
    if (cleanName.length > 50) {
      cleanName = cleanName.substring(0, 50).trim();
    }
    if (cleanName.isEmpty) cleanName = "Video_${task.id}";

    task.savePath = "${folder.path}/$cleanName.mp4";
    
    // ডাউনলোড শুরু করুন
    await _executeDownload(task);
  } catch (e) {
    _handleTaskError(task, e);
  }
}


}