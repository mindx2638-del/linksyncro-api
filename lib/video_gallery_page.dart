import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'video_player_page.dart';

// --- Shared Preferences Helper Logic ---
class VideoStorage {
  static const String _key = 'watched_videos_list';
  static Future<void> markAsWatched(String id) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> watched = prefs.getStringList(_key) ?? [];
    if (!watched.contains(id)) {
      watched.add(id);
      await prefs.setStringList(_key, watched);
    }
  }

  static Future<List<String>> getWatchedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }
}

class VideoGalleryPage extends StatefulWidget {
  const VideoGalleryPage({super.key});
  @override
  State<VideoGalleryPage> createState() => _VideoGalleryPageState();
}

class _VideoGalleryPageState extends State<VideoGalleryPage> {
  List<AssetPathEntity> _allFolders = [];
  List<AssetEntity> _allVideosGlobal = [];
  List<AssetEntity> _filteredVideosGlobal = [];
  List<String> _watchedIds = [];
  bool _isLoading = true;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
  final ps = await PhotoManager.requestPermissionExtend();
  if (ps.isAuth || ps.hasAccess) {
    final watched = await VideoStorage.getWatchedIds();
    final paths = await PhotoManager.getAssetPathList(type: RequestType.video);

    List<AssetPathEntity> folders = paths.where((path) => !path.isAll).toList();
    folders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final allAssetPath = paths.firstWhere((path) => path.isAll);
    final allVideos = await allAssetPath.getAssetListRange(start: 0, end: 5000);

    List<AssetEntity> sortedGlobalVideos = List.from(allVideos);
    sortedGlobalVideos.sort((a, b) {
      return (a.title ?? "").toLowerCase().compareTo((b.title ?? "").toLowerCase());
    });
    // -------------------------

    if (mounted) {
      setState(() {
        _allFolders = folders;
        _allVideosGlobal = sortedGlobalVideos; 
        _watchedIds = watched;
        _isLoading = false;
      });
    }
  } else {
    if (mounted) setState(() => _isLoading = false);
  }
  }

  void _searchAllVideos(String query) {
  setState(() {
    List<AssetEntity> filteredGlobal = _allVideosGlobal
        .where((v) => (v.title ?? "").toLowerCase().contains(query.toLowerCase()))
        .toList();
    filteredGlobal.sort((a, b) => (a.title ?? "").toLowerCase().compareTo((b.title ?? "").toLowerCase()));

    _filteredVideosGlobal = filteredGlobal;
  });
  }

 void _playVideoWithList(List<AssetEntity> assetList, int index) async {
  // ১. স্ক্রিনে একটি লোডিং ইন্ডিকেটর দেখান (পাথ বের করতে ১-২ সেকেন্ড লাগতে পারে)
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(
      child: CircularProgressIndicator(color: Colors.white),
    ),
  );

  try {
    // ২. ভিডিওটিকে 'Watched' হিসেবে মার্ক করুন
    await VideoStorage.markAsWatched(assetList[index].id);

    // ৩. সব ভিডিওর ফাইল পাথ (Path) আগেভাগে বের করে নিন
    // এটি করলে প্লেয়ার পেজে যাওয়ার পর ব্যাক বাটন চাপলে কোনো ল্যাগ হবে না
    List<File?> files = await Future.wait(
      assetList.map((v) => v.file).toList()
    );
    List<String> paths = files.map((f) => f?.path ?? "").toList();

    if (!mounted) return;
    
    // ৪. পাথ লোড হয়ে গেলে লোডিং ডায়ালগটি বন্ধ করুন
    Navigator.pop(context);

    // ৫. এবার সব ডাটা নিয়ে ভিডিও প্লেয়ার পেজে যান
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerPage(
          videoAssets: assetList,
          cachedPaths: paths, // ✅ নতুন প্যারামিটারটি এখানে পাস করুন
          index: index,
          title: assetList[index].title ?? "Video",
        ),
      ),
    );

    // ৬. প্লেয়ার থেকে ফিরে আসলে ডাটা রিফ্রেশ করুন
    _fetchData();
  } catch (e) {
    if (mounted) Navigator.pop(context);
    debugPrint("Error loading video paths: $e");
  }
}

  @override
Widget build(BuildContext context) {
  // PopScope ব্যবহার করা হয়েছে যাতে ফোনের ব্যাক বাটন/জেসচার হ্যান্ডেল করা যায়
  return PopScope(
    canPop: !_isSearching, // সার্চ না চললে সরাসরি ব্যাক হবে (হোমে যাবে)
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) return;
      if (_isSearching) {
        setState(() {
          _isSearching = false;
          _searchController.clear();
          _filteredVideosGlobal = [];
        });
      }
    },
    child: Scaffold(
      appBar: AppBar(
        // বাম পাশের ব্যাক আইকন
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_isSearching) {
              // সার্চ চললে শুধু সার্চ বন্ধ হবে
              setState(() {
                _isSearching = false;
                _searchController.clear();
                _filteredVideosGlobal = [];
              });
            } else {
              // সার্চ বন্ধ থাকলে আগের পেজে (হোমে) চলে যাবে
              Navigator.pop(context);
            }
          },
        ),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                    hintText: "Search all videos...", border: InputBorder.none),
                onChanged: _searchAllVideos,
              )
            : const Text("Video Gallery"),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _filteredVideosGlobal = [];
                }
              });
            },
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isSearching
              ? _buildGlobalSearchList()
              : _buildFolderList(),
    ),
  );
}

  Widget _buildFolderList() {
    return ListView.builder(
      itemCount: _allFolders.length,
      itemBuilder: (context, index) {
        final folder = _allFolders[index];
        return ListTile(
          leading: const Icon(Icons.folder, size: 40, color: Colors.amber),
          title: Text(folder.name),
          subtitle: FutureBuilder<int>(
            future: folder.assetCountAsync,
            builder: (_, s) => Text("${s.data ?? 0} videos"),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => FolderDetailsPage(folder: folder)),
            );
            _fetchData();
          },
        );
      },
    );
  }

  Widget _buildGlobalSearchList() {
    return ListView.builder(
      itemCount: _filteredVideosGlobal.length,
      itemBuilder: (context, index) {
        final video = _filteredVideosGlobal[index];
        bool isNew = !_watchedIds.contains(video.id);
        return ListTile(
          leading: _buildThumbnail(video, isNew),
          title: Text(video.title ?? "Video"),
          onTap: () => _playVideoWithList(_filteredVideosGlobal, index),
        );
      },
    );
  }

  Widget _buildThumbnail(AssetEntity video, bool isNew) {
    return Stack(
      children: [
        FutureBuilder(
          future: video.thumbnailDataWithSize(const ThumbnailSize(150, 100)),
          builder: (_, snap) => snap.hasData
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.memory(snap.data!, width: 80, height: 50, fit: BoxFit.cover))
              : Container(width: 80, height: 50, color: Colors.black12),
        ),
        if (isNew)
          Positioned(
            top: 0,
            left: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              color: Colors.green,
              child: const Text("NEW", style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }
}

// --- Folder Details Page ---
class FolderDetailsPage extends StatefulWidget {
  final AssetPathEntity folder;
  const FolderDetailsPage({super.key, required this.folder});

  @override
  State<FolderDetailsPage> createState() => _FolderDetailsPageState();
}

class _FolderDetailsPageState extends State<FolderDetailsPage> {
  List<AssetEntity> _videos = [];
  List<AssetEntity> _filteredVideos = [];
  List<String> _watchedIds = [];
  bool _isLoading = true;
  bool _isSearching = false;
  final TextEditingController _folderSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  // ভিডিও লোড করার লজিক (আগের মতোই রাখা হয়েছে)
  Future<void> _loadVideos() async {
    final watched = await VideoStorage.getWatchedIds();
    final videos = await widget.folder.getAssetListRange(start: 0, end: 5000);
    
    List<AssetEntity> sortedVideos = List.from(videos);
    sortedVideos.sort((a, b) {
      String nameA = (a.title ?? "").toLowerCase();
      String nameB = (b.title ?? "").toLowerCase();
      return nameA.compareTo(nameB);
    });

    if (mounted) {
      setState(() {
        _videos = sortedVideos;
        _filteredVideos = sortedVideos;
        _watchedIds = watched;
        _isLoading = false;
      });
    }
  }

  // ভিডিও প্লে করার নতুন ও ফাস্ট মেথড
  Future<void> _handleVideoTap(int index) async {
    final video = _filteredVideos[index];

    // ১. স্ক্রিনে একটি লোডিং দেখান (পাথ জেনারেট হতে সময় লাগতে পারে)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    try {
      // ২. 'Watched' হিসেবে মার্ক করুন
      await VideoStorage.markAsWatched(video.id);

      // ৩. সব ভিডিওর ফাইল পাথ (Paths) আগেভাগে বের করে নেওয়া (Critical for performance)
      List<File?> files = await Future.wait(
        _filteredVideos.map((v) => v.file).toList()
      );
      List<String> paths = files.map((f) => f?.path ?? "").toList();

      if (!mounted) return;
      Navigator.pop(context); // লোডিং বন্ধ করুন

      // ৪. 'cachedPaths' সহ প্লেয়ার ওপেন করুন
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerPage(
            videoAssets: _filteredVideos,
            cachedPaths: paths, // ✅ এটি আপনার বিল্ড এরর সমাধান করবে
            index: index,
            title: video.title ?? "Video",
          ),
        ),
      );
      
      // প্লেয়ার থেকে ফিরে আসলে লিস্ট রিফ্রেশ করুন
      _loadVideos();
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint("Error: $e");
    }
  }

  void _searchInFolder(String query) {
    setState(() {
      List<AssetEntity> filtered = _videos
          .where((v) => (v.title ?? "").toLowerCase().contains(query.toLowerCase()))
          .toList();
      filtered.sort((a, b) => (a.title ?? "").toLowerCase().compareTo((b.title ?? "").toLowerCase()));
      _filteredVideos = filtered;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _folderSearchController,
                autofocus: true,
                decoration: const InputDecoration(hintText: "Search in folder...", border: InputBorder.none),
                onChanged: _searchInFolder,
              )
            : Text(widget.folder.name),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _folderSearchController.clear();
                  _filteredVideos = _videos;
                }
              });
            },
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _filteredVideos.length,
              itemBuilder: (context, index) {
                final video = _filteredVideos[index];
                bool isNew = !_watchedIds.contains(video.id);
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: _buildThumbnail(video, isNew),
                  title: Text(video.title ?? "Video", maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text("${(video.duration ~/ 60)}:${(video.duration % 60).toString().padLeft(2, '0')}"),
                  trailing: const Icon(Icons.play_circle_outline),
                  onTap: () => _handleVideoTap(index), // ✅ নতুন হ্যান্ডলার কল করা হয়েছে
                );
              },
            ),
    );
  }

  Widget _buildThumbnail(AssetEntity video, bool isNew) {
    return Stack(
      children: [
        FutureBuilder(
          future: video.thumbnailDataWithSize(const ThumbnailSize(150, 100)),
          builder: (_, snap) => snap.hasData
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.memory(snap.data!, width: 80, height: 50, fit: BoxFit.cover))
              : Container(width: 80, height: 50, color: Colors.black12),
        ),
        if (isNew)
          Positioned(
            top: 0,
            left: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              color: Colors.green,
              child: const Text("NEW", style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }
}