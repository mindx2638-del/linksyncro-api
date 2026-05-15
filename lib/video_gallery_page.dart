import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart'; 
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_kit/media_kit.dart';
import 'video_player_page.dart';
import 'video_delete.dart'; 
import 'package:drag_select_grid_view/drag_select_grid_view.dart';
import 'dart:math'; 


class VideoStorage {
  static const String _key = 'watched_videos_list';
  static Future<void> markAsWatched(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final watched = prefs.getStringList(_key) ?? [];
    if (!watched.contains(id)) {
      watched.add(id);
      await prefs.setStringList(_key, watched);
    }
  }
  static Future<Set<String>> getWatchedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? []).toSet();
  }
}

class VideoGalleryPage extends StatefulWidget {
  const VideoGalleryPage({super.key});
  @override
  State<VideoGalleryPage> createState() => _VideoGalleryPageState();
}

class _VideoGalleryPageState extends State<VideoGalleryPage> {
  List<AssetPathEntity> _folders = [];
  List<AssetEntity> _allVideos = [];
  List<AssetEntity> _searchResult = [];
  Set<String> _watchedIds = {};
  bool _isLoading = true;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _folderScrollController = ScrollController();
  final ScrollController _searchScrollController = ScrollController();
  final dragFolderController = DragSelectGridViewController();
  final Map<String, String> _folderSizeCache = {};

  
  Future<String> _getFolderSize(AssetPathEntity folder) async {
  if (_folderSizeCache.containsKey(folder.id)) {
    return _folderSizeCache[folder.id]!;
  }
  try {
    final assets = await folder.getAssetListRange(start: 0, end: 5000);
    int totalBytes = 0;
    final List<File?> files = await Future.wait(assets.map((asset) => asset.file));  
    for (var file in files) {
      if (file != null) {
        totalBytes += await file.length();
      }
    }
    if (totalBytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB", "PB", "EB"];
    var i = (log(totalBytes) / log(1024)).floor();
    if (i >= suffixes.length) i = suffixes.length - 1;
    String result = "${(totalBytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}";
    _folderSizeCache[folder.id] = result;
    return result;
  } catch (e) {
    debugPrint("Error: $e");
    return "Unknown size";
  }
}

  @override
  void initState() {
    super.initState();
    MediaKit.ensureInitialized();
    _initGallery();
    dragFolderController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _folderScrollController.dispose();
    _searchController.dispose();
    _searchScrollController.dispose();
    dragFolderController.dispose(); 
    super.dispose();
  }

  Future<void> _initGallery() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth && !ps.hasAccess) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final watched = await VideoStorage.getWatchedIds();
    final paths = await PhotoManager.getAssetPathList(type: RequestType.video);
    List<AssetPathEntity> folders = paths.where((p) => !p.isAll).toList();
    folders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final allPath = paths.firstWhere((p) => p.isAll, orElse: () => paths.first);
    List<AssetEntity> allVideos = await allPath.getAssetListRange(start: 0, end: 5000);
    allVideos.sort((a, b) => (a.title ?? "").toLowerCase().compareTo((b.title ?? "").toLowerCase()));
    if (mounted) {
      setState(() {
        _folders = folders;
        _allVideos = allVideos;
        _watchedIds = watched;
        _isLoading = false;
      });
    }
  }

  void _onSearch(String query) {
    setState(() {
      _searchResult = _allVideos
          .where((v) => (v.title ?? "").toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _isSearching
              ? _buildVideoGrid(_searchResult)
              : _buildFolderList(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    // সিলেকশন মোডে আছে কি না তা চেক করা হচ্ছে
    final bool isSelecting = dragFolderController.value.isSelecting;
    final int selectedCount = dragFolderController.value.amount;

    return AppBar(
      elevation: 0.5,
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      
      // নতুন লজিক: সার্চ বা সিলেকশন মোডে থাকলে বাম পাশে একটি ব্যাক বাটন আসবে
      leading: (_isSearching || isSelecting)
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                setState(() {
                  if (isSelecting) {
                    dragFolderController.value = Selection.empty();
                  } else if (_isSearching) {
                    _isSearching = false;
                    _searchController.clear();
                    _searchResult = [];
                  }
                });
              },
            )
          : null,

      // ১. টাইটেল লজিক: আপনার আগের লজিক হুবহু রাখা হয়েছে
      title: isSelecting 
          ? Text("$selectedCount Selected", style: const TextStyle(fontWeight: FontWeight.bold))
          : (_isSearching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: "Search videos...", 
                    border: InputBorder.none
                  ),
                  onChanged: _onSearch,
                )
              : const Text("Video Library", style: TextStyle(fontWeight: FontWeight.bold))),
      
      actions: [
        // ২. অ্যাকশন বাটন লজিক: আপনার আগের লজিক হুবহু রাখা হয়েছে
        if (isSelecting)
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              setState(() {
                dragFolderController.value = Selection.empty();
              });
            },
          )
        else
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search_rounded),
            onPressed: () => setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) {
                _searchController.clear();
                _searchResult = [];
              }
            }),
          ),
      ],
    );
  }

  Widget _buildFolderList() {
  if (_folders.isEmpty) return const Center(child: Text("No video folders found"));
  
  final bool isSelecting = dragFolderController.value.isSelecting;
  final int selectedCount = dragFolderController.value.amount;

  return Stack(
    children: [
      Theme(
        data: Theme.of(context).copyWith(
          scrollbarTheme: ScrollbarThemeData(
            thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
              if (states.contains(WidgetState.dragged)) return Colors.blueAccent;
              if (states.contains(WidgetState.hovered)) return Colors.blue.withOpacity(0.7);
              return Colors.grey.withOpacity(0.4);
            }),
            thickness: WidgetStateProperty.all(6.0),
            radius: const Radius.circular(10),
            interactive: true,
          ),
        ),
        child: Scrollbar(
          controller: _folderScrollController,
          thumbVisibility: true,
          child: DragSelectGridView(
            gridController: dragFolderController,
            scrollController: _folderScrollController,
            triggerSelectionOnTap: false, 
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(16, 16, 16, isSelecting ? 100 : 20),
            itemCount: _folders.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 1, 
              mainAxisExtent: 95, 
              mainAxisSpacing: 12, 
            ),
            itemBuilder: (context, index, isSelected) {
              final folder = _folders[index];
              return Container(
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: isSelected ? Colors.blueAccent : Colors.transparent,
                    width: 2,
                  ),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                ),
                child: ListTile(
                  onTap: () async {
                    if (isSelecting) {
                      final Set<int> updatedIndexes = Set.from(dragFolderController.value.selectedIndexes);
                      if (updatedIndexes.contains(index)) {
                        updatedIndexes.remove(index);
                      } else {
                        updatedIndexes.add(index);
                      }
                      dragFolderController.value = Selection(updatedIndexes);
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => FolderDetailsPage(folder: folder)),
                      ).then((_) => _updateWatchedStatus()); 
                    }
                  },
                  onLongPress: () {
                    if (!isSelecting) {
                      dragFolderController.value = Selection({index});
                    }
                  },
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: isSelected ? Colors.blue : Colors.blue.withOpacity(0.1),
                    child: Icon(
                      isSelected ? Icons.check : Icons.folder_copy_rounded, 
                      color: isSelected ? Colors.white : Colors.blue
                    ),
                  ),
                  title: Text(folder.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: FutureBuilder<List<dynamic>>(
                    future: Future.wait([folder.assetCountAsync, _getFolderSize(folder)]),
                    builder: (context, snap) {
                      if (snap.hasData) {
                        return Text("${snap.data![0]} items  •  ${snap.data![1]}", 
                               style: const TextStyle(fontSize: 12, color: Colors.blueGrey));
                      }
                      return const Text("...", style: TextStyle(fontSize: 12));
                    },
                  ),
                  trailing: isSelected 
                    ? const Icon(Icons.check_circle, color: Colors.blue)
                    : const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                ),
              );
            },
          ),
        ),
      ),
      
      if (isSelecting)
        Positioned(
          bottom: 25, left: 50, right: 50,
          child: FloatingActionButton.extended(
            backgroundColor: Colors.redAccent,
            onPressed: () async {
              final selectedIndexes = dragFolderController.value.selectedIndexes;
              bool confirm = await VideoDelete.showConfirmDialog(
                context: context, 
                title: "Delete $selectedCount Folders?",
              );
              if (confirm) {
                for (var index in selectedIndexes) {
                  await VideoDelete.deleteFullFolder(_folders[index]);
                }
                dragFolderController.value = Selection.empty();
                _initGallery(); 
              }
            },
            label: Text("Delete $selectedCount Folders", 
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            icon: const Icon(Icons.delete_sweep, color: Colors.white),
          ),
        ),
    ],
  );
}

void _updateWatchedStatus() async {
  final watched = await VideoStorage.getWatchedIds();
  if (mounted) {
    setState(() {
      _watchedIds = watched;
    });
  }
}

  Widget _buildVideoGrid(List<AssetEntity> list) {
  return Theme(
    data: Theme.of(context).copyWith(
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.dragged)) return Colors.blueAccent;
          if (states.contains(WidgetState.hovered)) return Colors.blue.withOpacity(0.7);
          return Colors.grey.withOpacity(0.4);
        }),
        thickness: WidgetStateProperty.all(6.0),
        radius: const Radius.circular(10),
        interactive: true,
      ),
    ),
    child: Scrollbar(
      controller: _searchScrollController,
      thumbVisibility: true,
      interactive: true,
      child: GridView.builder(
        controller: _searchScrollController,
        physics: const ClampingScrollPhysics(), 
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, 
          crossAxisSpacing: 10, 
          mainAxisSpacing: 10, 
          childAspectRatio: 1.1,
        ),
        itemCount: list.length,
        itemBuilder: (context, index) => VideoCard(
          video: list[index],
          isWatched: _watchedIds.contains(list[index].id),
          onTap: () => _openPlayer(list, index),
        ),
      ),
    ),
  );
}

  Future<void> _openPlayer(List<AssetEntity> list, int index) async {
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerPage(
            videoAssets: list,
            cachedPaths: const [],
            index: index,
            title: list[index].title ?? "Video",
          ),
        ),
      );
      if (mounted) _initGallery(); 
    } catch (e) {
      debugPrint("Error: $e");
    }
  }
}

class FolderDetailsPage extends StatefulWidget {
  final AssetPathEntity folder;
  const FolderDetailsPage({super.key, required this.folder});
  @override
  State<FolderDetailsPage> createState() => _FolderDetailsPageState();
}

class _FolderDetailsPageState extends State<FolderDetailsPage> {
  List<AssetEntity> _videos = [];
  Set<String> _watchedIds = {};
  bool _isLoading = true;
  final ScrollController _scrollController = ScrollController();
  final dragController = DragSelectGridViewController();
  int _currentPage = 0;
  final int _pageSize = 20; 
  bool _hasMore = true;
  bool _isFetchingMore = false;

  @override
  void initState() {
    super.initState();
    _load(); 
    dragController.addListener(() {
      setState(() {}); 
    });
  }

  @override
  void dispose() {
    _scrollController.dispose(); 
    dragController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_isFetchingMore || !_hasMore) return;
    setState(() => _isFetchingMore = true);
    try {
      final watched = await VideoStorage.getWatchedIds();
      final List<AssetEntity> newVideos = await widget.folder.getAssetListRange(
        start: _currentPage * _pageSize,
        end: (_currentPage + 1) * _pageSize,
      );
      newVideos.sort((a, b) => (a.title ?? "").toLowerCase().compareTo((b.title ?? "").toLowerCase()));
      if (mounted) {
        setState(() {
          _videos.addAll(newVideos);
          _watchedIds = watched;
          _isLoading = false;
          _isFetchingMore = false;
          _currentPage++;
          if (newVideos.length < _pageSize) _hasMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isFetchingMore = false);
    }
  }
   
  String _formatBytes(int bytes) {
  if (bytes <= 0) return "0 B";
  const suffixes = ["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"];
  var i = (log(bytes) / log(1024)).floor();
  if (i >= suffixes.length) i = suffixes.length - 1;
  return "${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}";
}

  Future<String> _getTotalSelectedSize() async {
  final selectedIndexes = dragController.value.selectedIndexes; 
  if (selectedIndexes.isEmpty) return "0 B";
  final sizes = await Future.wait(
    selectedIndexes.map((index) async {
      final file = await _videos[index].file;
      return file != null ? await file.length() : 0;
    }),
  );

  int totalBytes = sizes.fold(0, (int sum, size) => sum + (size as int));
  return _formatBytes(totalBytes);
}

  Future<void> _deleteSelectedVideos() async {
    final selectedIndexes = dragController.value.selectedIndexes;
    if (selectedIndexes.isEmpty) return;
    final List<AssetEntity> toDelete = selectedIndexes.map((i) => _videos[i]).toList();
    final List<String> ids = toDelete.map((v) => v.id).toList();   
    try {
      final List<String> result = await PhotoManager.editor.deleteWithIds(ids);
      if (result.isNotEmpty) {
        setState(() {
          _videos.removeWhere((v) => toDelete.contains(v));
          dragController.value = Selection.empty(); 
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Deleted successfully")),
          );
        }
      }
    } catch (e) {
      debugPrint("Error deleting videos: $e");
    }
  }

  Future<void> _updateWatchedStatus() async {
    final watched = await VideoStorage.getWatchedIds();
    if (mounted) setState(() => _watchedIds = watched);
  }

  @override
Widget build(BuildContext context) {
  final bool isSelecting = dragController.value.isSelecting;
  final int selectedCount = dragController.value.amount;

  return PopScope(
    canPop: !isSelecting, 
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) return;
      if (isSelecting) {
        setState(() {
          dragController.value = Selection.empty();
        });
      }
    },
    child: Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        elevation: 0.5,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      
        leading: isSelecting 
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => dragController.value = Selection.empty()),
            ) 
          : null,
        title: isSelecting 
          ? Row(
              children: [
                Text("$selectedCount Selected", style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                FutureBuilder<String>(
                  future: _getTotalSelectedSize(),
                  builder: (context, snapshot) {
                    return Text(
                      snapshot.hasData ? "(${snapshot.data})" : "(...)",
                      style: const TextStyle(fontSize: 14, color: Colors.blueAccent, fontWeight: FontWeight.normal),
                    );
                  },
                ),
              ],
            )
          : Text(widget.folder.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (isSelecting)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => dragController.value = Selection.empty()),
            ),
        ],
      ),
  
      body: Theme(
        data: Theme.of(context).copyWith(
          scrollbarTheme: ScrollbarThemeData(
            thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
              if (states.contains(WidgetState.dragged)) return Colors.blueAccent;
              if (states.contains(WidgetState.hovered)) return Colors.blue.withOpacity(0.7);
              return Colors.grey.withOpacity(0.4);
            }),
            thickness: WidgetStateProperty.all(7.0),
            radius: const Radius.circular(10),
            interactive: true,
          ),
        ),
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: false,
          child: Stack(
            children: [
              _isLoading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : Column(
                      children: [
                        Expanded(
                          child: DragSelectGridView(
                            gridController: dragController,
                            scrollController: _scrollController,
                            physics: const ClampingScrollPhysics(), 
                            padding: const EdgeInsets.all(12),
                            itemCount: _videos.length,
                            autoScrollHotspotHeight: 100, 
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2, 
                              crossAxisSpacing: 12, 
                              mainAxisSpacing: 12, 
                              childAspectRatio: 1.1,
                            ),
                            itemBuilder: (context, index, isSelected) {
                              final video = _videos[index];

                              if (index >= _videos.length - 1 && _hasMore && !_isFetchingMore) {
                                WidgetsBinding.instance.addPostFrameCallback((_) => _load());
                              }

                              return Stack(
                                children: [
                                  VideoCard(
                                    video: video,
                                    isWatched: _watchedIds.contains(video.id),
                                    onTap: () {
                                      if (!isSelecting) {
                                        _playVideo(index);
                                      } else {
                                        // সিলেকশন মোডে ট্যাপ করলে সিলেক্ট/আনসিল্টে হবে
                                        final updatedIndexes = Set<int>.from(dragController.value.selectedIndexes);
                                        if (updatedIndexes.contains(index)) {
                                          updatedIndexes.remove(index);
                                        } else {
                                          updatedIndexes.add(index);
                                        }
                                        dragController.value = Selection(updatedIndexes);
                                      }
                                    },
                                  ),
                                  if (isSelected)
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withOpacity(0.3), 
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.blueAccent, width: 2),
                                      ),
                                      child: const Center(
                                        child: Icon(Icons.check_circle, color: Colors.white, size: 30),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                        if (_isFetchingMore)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
              
              if (isSelecting)
                Positioned(
                  bottom: 25,
                  left: 50,
                  right: 50,
                  child: FloatingActionButton.extended(
                    backgroundColor: Colors.redAccent,
                    onPressed: _deleteSelectedVideos,
                    label: Text("Delete $selectedCount Videos", 
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    icon: const Icon(Icons.delete_forever, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}



  Future<void> _playVideo(int index) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerPage(
          videoAssets: _videos, 
          cachedPaths: const [], 
          index: index,
          title: _videos[index].title ?? "Video",
        ),
      ),
    );
    if (mounted) _updateWatchedStatus();
  }
}

// --- Fixed Video Card Component ---
class VideoCard extends StatelessWidget {
  final AssetEntity video;
  final bool isWatched;
  final VoidCallback onTap;

  const VideoCard({super.key, required this.video, required this.isWatched, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withOpacity(0.05)),
        ),
        child: Stack(
          children: [
            // Fixed Thumbnail Logic
            Positioned.fill(
              child: AssetEntityImage(
                video,
                isOriginal: false,
                thumbnailSize: const ThumbnailSize(300, 300),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(color: Colors.grey[200]),
              ),
            ),
            
              Positioned(
      top: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          _formatDateTime(video.createDateTime),
          style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold),
        ),
      ),
    ),

            // Watched Effect
            if (isWatched)
  const Positioned.fill(
    child: Center(
      child: Icon(
        Icons.play_circle_outline,
        color: Colors.white70, 
        size: 40,
      ),
    ),
  ),


            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                  ),
                ),
              ),
            ),
            
            if (!isWatched)
              Positioned(
                top: 8, left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(4)),
                  child: const Text("NEW", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),

            Positioned(
              bottom: 25, right: 8,
              child: Text(
                _formatDuration(video.duration),
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
            Positioned(
              bottom: 5, left: 8, right: 8,
              child: Text(
                video.title ?? "Unknown",
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? "${d.inHours}:$m:$s" : "$m:$s";
  }

   String _formatDateTime(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final year = date.year;
    
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    final month = months[date.month - 1];

    int hour = date.hour;
    final String period = hour >= 12 ? "PM" : "AM";
    hour = hour % 12;
    hour = hour == 0 ? 12 : hour; 
    final minute = date.minute.toString().padLeft(2, '0');

    return "$day $month, $year | ${hour.toString().padLeft(2, '0')}:$minute $period";
  }
} 
