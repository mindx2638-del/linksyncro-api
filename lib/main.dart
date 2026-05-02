import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:media_scanner/media_scanner.dart';
import 'package:path_provider/path_provider.dart';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

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
  String? videoUrlOnly;
  String? audioUrlOnly;
  String? savePath;
  double progress;
  String statusText;
  bool isProcessing;
  bool isPaused;
  bool isFinished;
  bool isHighQuality;


  DownloadTask({
    required this.id,
    required this.inputUrl,
    this.videoTitle,
    this.thumbnailUrl,
    this.downloadUrl,
    this.videoUrlOnly, // এটি যোগ করুন
    this.audioUrlOnly, // এটি যোগ করুন
    this.savePath,
    this.progress = 0,
    this.statusText = "Analyzing...",
    this.isProcessing = true,
    this.isPaused = false,
    this.isFinished = false,
    this.isHighQuality = false, 
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

@override
void initState() {
  super.initState();
  _checkPermission();
  
  // ১. আইসোলেট পোর্ট সেটআপ (পুরানো ম্যাপিং থাকলে রিমুভ করে নতুন করে সেট করা)
  IsolateNameServer.removePortNameMapping('downloader_send_port');
  IsolateNameServer.registerPortWithName(_port.sendPort, 'downloader_send_port');
  
  // ২. ডাউনলোডার লিসেনার
  _port.listen((dynamic data) {
    String id = data[0];
    int status = data[1]; // ৩ = Success, ৪ = Failed, ২ = Running
    int progress = data[2];

    setState(() {
      // বর্তমান লিস্ট থেকে আইডি অনুযায়ী টাস্কটি খুঁজে বের করা
      final task = _downloadTasks.firstWhere(
        (t) => t.id == id, 
        orElse: () => DownloadTask(id: "", inputUrl: "")
      );
      
      if (task.id.isNotEmpty) {
        // প্রগ্রেস আপডেট (প্রসেসিং স্টেজে ১.০ রাখার জন্য চেক)
        if (progress != -1 && !task.statusText.contains("Merging")) {
          task.progress = progress / 100;
        }

        // ৩. স্ট্যাটাস অনুযায়ী স্মার্ট লজিক
        if (status == 3) { // ডাউনলোড সফল (Success)
          
          if (task.isHighQuality) {
            // ৩.১ হাই কোয়ালিটি লজিক: ভিডিও শেষ হলে অডিও ধরবে, অডিও শেষ হলে মার্জ করবে
            if (task.statusText.contains("Video")) {
              task.statusText = "Downloading Audio (HQ)...";
              _downloadHQAudio(task); // অডিও ডাউনলোড শুরু করার ফাংশন
            } 
            else if (task.statusText.contains("Audio")) {
              task.statusText = "Merging Crystal Clear Video...";
              task.isProcessing = true;
              task.progress = 0.9; // মার্জ হওয়ার সময় প্রগ্রেস আটকে রাখা
              _mergeHQFiles(task); // FFmpeg মার্জ কল
            }
          } 
          else {
            // ৩.২ সাধারণ ভিডিওর জন্য সরাসরি ফিনিশ
            task.isFinished = true;
            task.isProcessing = false;
            task.progress = 1.0;
            task.statusText = "Saved to Gallery";
          }
          
        } else if (status == 4) { // ডাউনলোড ফেইলড
          task.statusText = "Download Failed";
          task.isProcessing = false;
          task.isPaused = false;
        } else if (status == 2) { // ডাউনলোড চলছে (Running)
          if (!task.statusText.contains("Merging")) {
             task.statusText = task.isHighQuality 
                 ? (task.statusText.contains("Audio") ? "Downloading Audio (HQ)..." : "Downloading Video (HQ)...")
                 : "Downloading...";
          }
        } else if (status == 0 || status == 1) { // কিউতে আছে
          task.statusText = "Waiting in queue...";
        }
      }
    });
  });

  FlutterDownloader.registerCallback(downloadCallback);
}


@override
void dispose() {
  IsolateNameServer.removePortNameMapping('downloader_send_port');
  _urlController.dispose();
  _port.close(); // পোর্ট বন্ধ করা
  super.dispose();
}

Future<void> _executeHQDownload(DownloadTask task) async {
  try {
    final saveDir = task.savePath!.substring(0, task.savePath!.lastIndexOf('/'));
    
    // প্রথমে শুধু ভিডিও ডাউনলোড হবে
    final vTaskId = await FlutterDownloader.enqueue(
      url: task.videoUrlOnly!,
      savedDir: saveDir,
      fileName: "temp_v_${task.id}.mp4",
      showNotification: true,
      saveInPublicStorage: false,
    );

    if (vTaskId != null) {
      setState(() {
        task.id = vTaskId; // ভিডিওর আইডি সেট হলো
        task.statusText = "Downloading Video (HQ)...";
      });
    }
  } catch (e) {
    _handleTaskError(task, "HQ Video download failed");
  }
}

// ২. অডিও ডাউনলোডের দ্বিতীয় ধাপ
Future<void> _downloadHQAudio(DownloadTask task) async {
  try {
    final saveDir = task.savePath!.substring(0, task.savePath!.lastIndexOf('/'));
    final aTaskId = await FlutterDownloader.enqueue(
      url: task.audioUrlOnly!,
      savedDir: saveDir,
      fileName: "temp_a_${task.id}.mp3",
      showNotification: false, // অডিওর জন্য আলাদা নোটিফিকেশন দরকার নেই
      saveInPublicStorage: false,
    );

    if (aTaskId != null) {
      setState(() {
        task.id = aTaskId; // এখন অডিও আইডি ট্র্যাক হবে
        task.statusText = "Downloading Audio (HQ)...";
      });
    }
  } catch (e) {
    _handleTaskError(task, "HQ Audio download failed");
  }
}

// ৩. মার্জ করার কমান্ড (একটু আপডেট করা হয়েছে কোয়ালিটি ঠিক রাখতে)
Future<void> _mergeHQFiles(DownloadTask task) async {
  final saveDir = task.savePath!.substring(0, task.savePath!.lastIndexOf('/'));
  final videoFile = "$saveDir/temp_v_${task.id}.mp4";
  final audioFile = "$saveDir/temp_a_${task.id}.mp3";
  final finalFile = task.savePath!;

  // কমান্ড: -c copy দিলে কোয়ালিটি একদম অরিজিনাল থাকে এবং দ্রুত হয়
  final command = "-i $videoFile -i $audioFile -c copy -map 0:v:0 -map 1:a:0 -y $finalFile";

  await FFmpegKit.execute(command).then((session) async {
    final returnCode = await session.getReturnCode();
    
    if (ReturnCode.isSuccess(returnCode)) {
      if (await File(videoFile).exists()) await File(videoFile).delete();
      if (await File(audioFile).exists()) await File(audioFile).delete();

      setState(() {
        task.isFinished = true;
        task.isProcessing = false;
        task.statusText = "Saved: 1080p Crystal Clear";
        task.progress = 1.0;
      });
      MediaScanner.loadMedia(path: finalFile);
    } else {
      _handleTaskError(task, "FFmpeg Merge Failed");
    }
  });
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
    // ১. সার্ভার থেকে লিঙ্ক রেজলভ করা
    final result = await _resolveLink(task.inputUrl);
    
    setState(() {
      task.videoTitle = result['title'] ?? "Video_${task.id}";
      task.thumbnailUrl = result['thumbnail'];
      
      // ব্যাকএন্ড থেকে আসা কী-গুলোর নাম পাইথন কোডের সাথে মিল রেখে চেক করা
      if (result['video_url'] != null && result['audio_url'] != null) {
        task.videoUrlOnly = result['video_url'];
        task.audioUrlOnly = result['audio_url'];
        task.isHighQuality = true;
        task.downloadUrl = null; 
        task.statusText = "Downloading Video (HQ)..."; // এটি খুবই গুরুত্বপূর্ণ
      } else {
        // Fallback: যদি আলাদা লিঙ্ক না থাকে
        task.downloadUrl = result['url'] ?? result['video_url'];
        task.isHighQuality = false;
        task.statusText = "Starting download...";
      }
    });

    // ২. বৈধতা চেক
    if (task.downloadUrl == null && !task.isHighQuality) {
      throw "Could not find a valid download link.";
    }

    // ৩. স্টোরেজ ডিরেক্টরি সেটআপ
    final directory = await getExternalStorageDirectory();
    if (directory == null) throw "Could not access storage directory.";
    
    final folder = Directory("${directory.path}/LinkSyncro");
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    // ৪. ফাইল নেম ক্লিনিং
    String cleanName = task.videoTitle!.replaceAll(RegExp(r'[<>:"/\\|?*]'), '').trim();
    if (cleanName.length > 50) {
      cleanName = cleanName.substring(0, 50).trim();
    }
    if (cleanName.isEmpty) {
      cleanName = "Video_${DateTime.now().millisecondsSinceEpoch}";
    }
    
    // ৫. ফাইনাল সেভ পাথ সেট করা
    task.savePath = "${folder.path}/$cleanName.mp4";

    // ৬. ডাউনলোডের ধরণ অনুযায়ী মেথড কল করা
    if (task.isHighQuality) {
      // হাই কোয়ালিটি: এখানে আমরা ভিডিও ডাউনলোড দিয়ে শুরু করব
      await _executeHQDownload(task); 
    } else {
      // সাধারণ ডাউনলোড (ভিডিও+অডিও এক ফাইলে)
      await _executeDownload(task);
    }

  } catch (e) {
    debugPrint("StartDownload Error: $e");
    _handleTaskError(task, e.toString());
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
  String? lastError;

  // ১. ইউটিউব চেক (আলাদা try-catch যাতে এটি ফেল করলে ফেসবুক বা রেন্ডার সার্ভার কাজ করে)
  if (_ytService.isYouTubeLink(input)) {
    try {
      return await _ytService.getVideoDetails(input);
    } catch (e) {
      lastError = e.toString();
      debugPrint("YouTube Service Failed: $e");
    }
  }

  // ২. ফেসবুক চেক
  if (_fbService.isFacebookLink(input)) {
    try {
      return await _fbService.getVideoDetails(input);
    } catch (e) {
      lastError = e.toString();
      debugPrint("Facebook Service Failed: $e");
      // এখানে stop না করে নিচে রেন্ডার সার্ভারগুলো ট্রাই করবে
    }
  }

  // ৩. ইন্সটাগ্রাম চেক
  if (_igService.isInstagramLink(input)) {
    try {
      return await _igService.getVideoDetails(input);
    } catch (e) {
      lastError = e.toString();
      debugPrint("Instagram Service Failed: $e");
    }
  }

  // ৪. যদি ওপরের সার্ভিসগুলো কাজ না করে, তবে রেন্ডার সার্ভারগুলোর লুপ চলবে
  final List<String> customApiUrls = [
    "https://linksyncro-api-f1k4.onrender.com/exec",
    "https://linksyncro-api-1.onrender.com/exec",
    "https://linksyncro-api-b08a.onrender.com/exec", 
  ];

  for (String apiUrl in customApiUrls) {
    try {
      debugPrint("Trying Render Server: $apiUrl");
      final uri = Uri.parse("$apiUrl?url=${Uri.encodeComponent(input)}");
      
      // টাইমআউট কমিয়ে ১০ সেকেন্ড করুন, যাতে বন্ধ সার্ভারে বসে না থাকে
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      lastError = e.toString();
      debugPrint("Render Server $apiUrl Failed: $e");
      continue; // এরর হলেও পরের লিংকে যাবে
    }
  }

  // ৫. সবশেষে গুগল স্ক্রিপ্ট (একদম শেষ ভরসা)
  try {
    const String googleScriptUrl = "https://script.google.com/macros/s/AKfycbyBb_EitRWdtVUHAeBCpC2KERIZR7Ik7p9EBtGrKBv2Q8cu4bFKl0WXkwENh2p1LWQalA/exec";
    final uri = Uri.parse("$googleScriptUrl?url=${Uri.encodeComponent(input)}");
    final response = await http.get(uri).timeout(const Duration(seconds: 25));
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    }
  } catch (e) {
    lastError = e.toString();
  }

  // যদি কোনো কিছুই কাজ না করে
  throw "All servers are currently unavailable. ($lastError)";
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