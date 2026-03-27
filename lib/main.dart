import 'dart:isolate';
import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dio/dio.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ১. ডাউনলোডার ইনিশিয়ালাইজেশন
  await FlutterDownloader.initialize(
    debug: true, 
    ignoreSsl: true
  );

  runApp(const LinkSyncro());
}

class LinkSyncro extends StatelessWidget {
  const LinkSyncro({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LinkSyncro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blueAccent,
      ),
      home: const DownloadScreen(),
    );
  }
}

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = false;
  final ReceivePort _port = ReceivePort(); 

  @override
  void initState() {
    super.initState();
    // ২. ডাউনলোড প্রগ্রেস ট্র্যাক করার জন্য পোর্ট সেটআপ
    IsolateNameServer.registerPortWithName(_port.sendPort, 'downloader_send_port');
    _port.listen((dynamic data) {
      setState(() {});
    });

    FlutterDownloader.registerCallback(downloadCallback);
  }

  @override
  void dispose() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    _urlController.dispose();
    super.dispose();
  }

  @pragma('vm:entry-point')
  static void downloadCallback(String id, int status, int progress) {
    final SendPort? send = IsolateNameServer.lookupPortByName('downloader_send_port');
    send?.send([id, status, progress]);
  }

  // ৩. মূল ডাউনলোড ফাংশন
  Future<void> _handleDownload(String userUrl) async {
    if (userUrl.isEmpty) return;

    // পারমিশন চেক (অ্যান্ড্রয়েড ১৩+ এর জন্য আপডেট করা)
    if (Platform.isAndroid) {
      await [
        Permission.storage,
        Permission.videos,
        Permission.notification,
      ].request();
    }

    setState(() => _isLoading = true);

    try {
      // আপনার পাইথন সার্ভারের আইপি এখানে বসানো হয়েছে
      // টার্মিনালে যে আইপি দেখাচ্ছে সেটিই এখানে ব্যবহার করা হয়েছে
      String myServerUrl = "http://10.47.46.93:5000/get_video?url=$userUrl";
      
      var response = await Dio().get(myServerUrl);
      
      if (response.data['status'] == 'success') {
        String directUrl = response.data['url']; // ভিডিওর আসল লিঙ্ক
        
        // ডাউনলোড ফোল্ডার পাথ গেট করা
        Directory? downloadsDirectory = await getExternalStorageDirectory();
        String savedPath = "/storage/emulated/0/Download"; // সরাসরি ডাউনলোড ফোল্ডার

        // ডাউনলোড শুরু
        await FlutterDownloader.enqueue(
          url: directUrl,
          savedDir: savedPath,
          fileName: "LinkSyncro_${DateTime.now().millisecondsSinceEpoch}.mp4",
          showNotification: true,
          openFileFromNotification: true,
          saveInPublicStorage: true,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Download Started! Check notifications.")),
        );
      } else {
        throw Exception("Server could not find video link");
      }
    } catch (e) {
      print("Error details: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error: Server not running or Connection failed")),
      );
    } finally {
      setState(() => _isLoading = false);
      _urlController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("LinkSyncro", 
                  style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                const Text("Pro Social Media Downloader", 
                  style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 50),
                
                TextField(
                  controller: _urlController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Paste video link here...",
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    prefixIcon: const Icon(Icons.link, color: Colors.blueAccent),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 25),
                
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : () => _handleDownload(_urlController.text),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("DOWNLOAD NOW", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
                const Spacer(),
                const Center(child: Text("Version 1.0.0", style: TextStyle(color: Colors.white24))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
