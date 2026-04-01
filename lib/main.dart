import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:media_scanner/media_scanner.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
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
  CancelToken cancelToken;

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
  }) : cancelToken = CancelToken();
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
  final List<DownloadTask> _downloadTasks = [];
  
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
      final result = await _resolveLink(task.inputUrl);
      
      setState(() {
        task.downloadUrl = result['url'];
        task.videoTitle = result['title'] ?? "Video_${task.id}";
        task.thumbnailUrl = result['thumbnail'];
      });

      if (task.downloadUrl == null) throw "Invalid response from server";

      const root = "/storage/emulated/0";
      final folder = Directory("$root/Download/LinkSyncro");
      if (!await folder.exists()) await folder.create(recursive: true);

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

  // --- আপডেট করা Apps Script Proxy লজিক ---
  Future<Map<String, dynamic>> _resolveLink(String input) async {
    // তোমার Apps Script URL
    const String proxyUrl = "https://script.google.com/macros/s/AKfycbxFj9-cyjRj492q8ilK0r-9EzXucNGzFaZrGhTclXNeob4L9W7qL9S-TEsaquLOhGINwA/exec";
    
    final uri = Uri.parse("$proxyUrl?url=${Uri.encodeComponent(input)}");

    final response = await http.get(uri).timeout(const Duration(seconds: 45));

    if (response.statusCode == 200) {
      // utf8.decode ব্যবহার করা হয়েছে যাতে বাংলা নাম ঠিক থাকে
      final decodedData = jsonDecode(utf8.decode(response.bodyBytes));
      
      if (decodedData['status'] == 'success' || decodedData['url'] != null) {
        return decodedData;
      } else {
        throw "Extraction failed";
      }
    } else if (response.statusCode == 429) {
      throw "Rate limit: Wait a moment";
    }
    throw "Proxy Error: ${response.statusCode}";
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
      displayMsg = "Storage Error";
    } else if (e.toString().contains("429")) {
      displayMsg = "Too many requests";
    } else if (e.toString().contains("TimeoutException")) {
      displayMsg = "Connection Timeout";
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
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.indigo,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  const Text("LINKSYNCRO PRO", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 30),
                  Container(
                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(15)),
                    child: TextField(
                      controller: _urlController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Paste link here...",
                        hintStyle: const TextStyle(color: Colors.white54),
                        prefixIcon: const Icon(Icons.link, color: Colors.indigo),
                        suffixIcon: IconButton(icon: const Icon(Icons.paste, color: Colors.indigo), onPressed: _pasteFromClipboard),
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
                    onPressed: _addNewDownload,
                    child: const Text("DOWNLOAD NOW", style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _downloadTasks.length,
                itemBuilder: (context, index) {
                  final task = _downloadTasks[index];
                  return _buildDownloadCard(task);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadCard(DownloadTask task) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF252545),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 80,
                height: 50,
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: task.thumbnailUrl != null 
                    ? Image.network(task.thumbnailUrl!, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.video_collection, color: Colors.white54))
                    : const Icon(Icons.video_collection, color: Colors.white54),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.videoTitle ?? "Processing...",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)
                    ),
                    const SizedBox(height: 4),
                    Text(task.statusText, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  ],
                ),
              ),
              if (!task.isFinished) ...[
                IconButton(
                  icon: Icon(task.isPaused ? Icons.play_arrow : Icons.pause, color: Colors.white),
                  onPressed: () => _togglePauseResume(task),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.redAccent),
                  onPressed: () => _cancelDownload(task),
                ),
              ] else ...[
                const Icon(Icons.check_circle, color: Colors.greenAccent),
              ],
            ],
          ),
          const SizedBox(height: 20),
          LinearProgressIndicator(
            value: task.progress,
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation(task.isFinished ? Colors.greenAccent : Colors.blueAccent),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("${(task.progress * 100).toStringAsFixed(0)}%", style: const TextStyle(color: Colors.white70)),
              if (task.isFinished) const Text("Done", style: TextStyle(color: Colors.greenAccent)),
            ],
          ),
        ],
      ),
    );
  }
}