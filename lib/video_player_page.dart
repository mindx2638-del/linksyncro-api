import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:photo_manager/photo_manager.dart'; 
import 'package:shared_preferences/shared_preferences.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:audio_service/audio_service.dart';
import 'my_audio_handler.dart'; 
import 'main.dart';


class VideoPlayerPage extends StatefulWidget {
  final List<AssetEntity> videoAssets;
  final List<String> cachedPaths; 
  final int index;
  final String title;

  const VideoPlayerPage({
    super.key,
    required this.videoAssets,
    required this.cachedPaths, 
    required this.index,
    required this.title,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class VideoStorage {
  static const String _key = 'watched_videos_list';
  
  // এখানে আন্ডারস্কোর (_) যুক্ত করে দেওয়া হয়েছে যাতে নিচের মেথডগুলোর সাথে মেলে
  static const String _positionKeyPrefix = 'video_pos_'; 

  // ভিডিও দেখা হয়েছে কিনা মার্ক করা
  static Future<void> markAsWatched(String id) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> watched = prefs.getStringList(_key) ?? [];
    if (!watched.contains(id)) {
      watched.add(id);
      await prefs.setStringList(_key, watched);
    }
  }

  // দেখা ভিডিওর আইডি লিস্ট পাওয়া
  static Future<List<String>> getWatchedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  // ভিডিওর বর্তমান পজিশন সেভ করা
  static Future<void> savePosition(String id, Duration position) async {
    final prefs = await SharedPreferences.getInstance();
    // এখানে এখন '_positionKeyPrefix' কাজ করবে
    await prefs.setInt('$_positionKeyPrefix$id', position.inMilliseconds);
  }

  // সেভ করা পজিশন ফিরে পাওয়া
  static Future<Duration> getPosition(String id) async {
    final prefs = await SharedPreferences.getInstance();
    int? ms = prefs.getInt('$_positionKeyPrefix$id');
    if (ms != null) {
      return Duration(milliseconds: ms);
    }
    return Duration.zero;
  }

  // পজিশন ডিলিট করা
  static Future<void> clearPosition(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_positionKeyPrefix$id');
  }
}

class _VideoPlayerPageState extends State<VideoPlayerPage> with TickerProviderStateMixin, WidgetsBindingObserver {
  VideoPlayerController? _controller;
  VideoPlayerController? _nextController;
  VideoPlayerController? _prevController;
  late TransformationController _transformController;
  late int currentIndex;
  bool _isLocked = false;
  bool _showControls = true;
  int _zoomStep = 0;
  double _brightness = 0.5;
  double _volume = 0.5;
  bool _showBrightness = false;
  bool _showVolume = false;
  bool _showSeekIndicator = false;
  String _seekTimeText = "";
  bool _showRewindAnim = false;
  bool _showForwardAnim = false;
  Timer? _hideTimer;
  bool _isInitializing = true; 
  bool _isFastForwarding = false; 
  bool _isSlowingDown = false;
  int _loopMode = 0;
  bool _isBottomArea(Offset pos, Size size) {const double controlHeight = 140.0; return pos.dy > (size.height - controlHeight);}
  bool _isExtraMenuOpen = false;
  bool _isBackgroundMode = false;

  @override
  void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this); 
  currentIndex = widget.index; 
  _transformController = TransformationController();
    VolumeController().showSystemUI = false; 
  _initPlayer(currentIndex);
  }

  void _setOrientation() {
    if (_controller != null && _controller!.value.isInitialized) {
      final size = _controller!.value.size;
      if (size.height > size.width) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _initPlayer(int index) async {
  setState(() => _isInitializing = true);
  
  // ভিডিওর আইডি আলাদা ভেরিয়েবলে নিয়ে রাখা
  final String videoId = widget.videoAssets[index].id;

  // ভিডিও ওয়াচড হিসেবে মার্ক করা
  await VideoStorage.markAsWatched(videoId);

  // পুরোনো কন্ট্রোলার রিমুভ ও ডিসপোজ করা
  _controller?.removeListener(_videoListener);
  await _controller?.dispose();
  _controller = null;

  try {
    final File? file = await widget.videoAssets[index].file;
    if (file != null) {
      _controller = VideoPlayerController.file(file);
      await _controller!.initialize();

      if (!mounted || _controller == null || !_controller!.value.isInitialized) return;

      // --- পরিবর্তন এখানে: সেভ করা পজিশন চেক এবং সিক করা ---
      final Duration savedPosition = await VideoStorage.getPosition(videoId);
      if (savedPosition > Duration.zero && savedPosition < _controller!.value.duration) {
        // যদি ভিডিওর ৯৫% এর বেশি দেখা হয়ে যায়, তবে শুরু থেকে চালানো ভালো (ঐচ্ছিক লজিক)
        await _controller!.seekTo(savedPosition);
      }
      // ------------------------------------------------

      _setOrientation();
      _controller!.play();

      // অডিও হ্যান্ডলার আপডেট লজিক
      final List<String> titles = widget.videoAssets.map((v) => v.title ?? "Video").toList();
      final List<String> ids = widget.videoAssets.map((v) => v.id).toList();

      await audioHandler.setPlaylist(
        widget.cachedPaths,
        index,
        titles,
        ids,
        shouldPlay: false,
      );

      await _controller!.setPlaybackSpeed(1.0);
      _controller!.addListener(_videoListener);

      // ব্রাইটনেস এবং ভলিউম সেটআপ
      try {
        _brightness = await ScreenBrightness().current;
      } catch (_) {
        _brightness = 0.5;
      }
      
      _volume = await VolumeController().getVolume();

      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _showSeekIndicator = false;
      });

      _startHideTimer();

      // ভিডিও প্রি-লোড করা
      _preloadNextVideo(index + 1);
      _preloadPrevVideo(index - 1);
    } else {
      _handlePlayerError("Video file not found!");
    }
  } catch (e) {
    _handlePlayerError("Could not play video: ${e.toString()}");
  }
}

void _handlePlayerError(String message) {
  if (mounted) {
    setState(() => _isInitializing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

  Future<void> _preloadNextVideo(int nextIndex) async {
    if (nextIndex >= widget.videoAssets.length) return;
    await _nextController?.dispose();
    
    final File? nextFile = await widget.videoAssets[nextIndex].file;
    if (nextFile != null) {
      _nextController = VideoPlayerController.file(nextFile);
      try {
        await _nextController!.initialize();
      } catch (e) {
        debugPrint("Preload error: $e");
      }
    }
  }

  Future<void> _preloadPrevVideo(int prevIndex) async {
  if (prevIndex < 0) return;
  await _prevController?.dispose();
  final File? file = await widget.videoAssets[prevIndex].file;
  if (file != null) {
    _prevController = VideoPlayerController.file(file);
    try { await _prevController!.initialize(); } catch (e) { debugPrint(e.toString()); }
  }
}

Future<void> _disposePreloadControllers() async {
  await _nextController?.dispose();
  await _prevController?.dispose();
  _nextController = null;
  _prevController = null;
}

 void _videoListener() {
  if (!mounted || _controller == null || !_controller!.value.isInitialized) return;

  final bool isFinished = _controller!.value.position >= _controller!.value.duration;

  if (isFinished) {
  _controller!.removeListener(_videoListener);

  // 🔁 Single video loop
  if (_loopMode == 1) {
    _controller!.seekTo(Duration.zero);
    _controller!.play();
    _controller!.addListener(_videoListener);
    return;
  }

  // 🔂 All video loop
  if (_loopMode == 2) {
    if (currentIndex < widget.videoAssets.length - 1) {
      _changeVideo(currentIndex + 1);
    } else {
      _changeVideo(0); 
    }
    return;
  }

  // Normal
  if (currentIndex < widget.videoAssets.length - 1) {
    _changeVideo(currentIndex + 1);
  }
}
  
  if (mounted) setState(() {});
}

  void _changeVideo(int newIndex) async {
  if (newIndex < 0 || newIndex >= widget.videoAssets.length) return;

  // --- পরিবর্তন এখানে: ভিডিও পরিবর্তনের ঠিক আগে বর্তমান পজিশন সেভ করা ---
  if (_controller != null && _controller!.value.isInitialized) {
    await VideoStorage.savePosition(
      widget.videoAssets[currentIndex].id, 
      _controller!.value.position,
    );
  }
  // ------------------------------------------------------------------

  _controller?.removeListener(_videoListener);
  _hideTimer?.cancel();

  setState(() {
    _isFastForwarding = false;
    _isSlowingDown = false;
    _showBrightness = false;
    _showVolume = false;
    _showSeekIndicator = false;
    _showRewindAnim = false;
    _showForwardAnim = false;
    _seekTimeText = "";
  });

  bool swapped = false;

  // ১. নেক্সট ভিডিও সোয়াপ লজিক (Preload থাকলে)
  if (newIndex == currentIndex + 1 && _nextController != null && _nextController!.value.isInitialized) {
    _prevController?.dispose();
    _prevController = _controller;
    _controller = _nextController;
    _controller!.addListener(_videoListener);
    _nextController = null;
    swapped = true;
  } 
  // ২. প্রিভিয়াস ভিডিও সোয়াপ লজিক (Preload থাকলে)
  else if (newIndex == currentIndex - 1 && _prevController != null && _prevController!.value.isInitialized) {
    _nextController?.dispose();
    _nextController = _controller;
    _controller = _prevController;
    _controller!.addListener(_videoListener);
    _prevController = null;
    swapped = true;
  }

  if (swapped) {
    setState(() {
      currentIndex = newIndex;
      _isInitializing = false;
      _transformController.value = Matrix4.identity();
      _zoomStep = 0;
    });

    // --- পরিবর্তন এখানে: সোয়াপ করা ভিডিওর সেভ করা পজিশনে সিক করা ---
    final Duration savedPos = await VideoStorage.getPosition(widget.videoAssets[currentIndex].id);
    if (savedPos > Duration.zero) {
      await _controller!.seekTo(savedPos);
    }
    // -----------------------------------------------------------

    await _controller!.setPlaybackSpeed(1.0);
    _controller!.play();
    _setOrientation();
    _startHideTimer();

    _preloadNextVideo(currentIndex + 1);
    _preloadPrevVideo(currentIndex - 1);
    await VideoStorage.markAsWatched(widget.videoAssets[currentIndex].id);
    return;
  }

  // ৩. যদি প্রি-লোড না থাকে (র‍্যান্ডম ভিডিওতে ক্লিক করলে)
  await _disposePreloadControllers();
  setState(() {
    currentIndex = newIndex;
    _isInitializing = true;
    if (_controller != null) {
      _controller!.dispose();
      _controller = null;
    }
    _transformController.value = Matrix4.identity();
    _zoomStep = 0;
  });

  if (!mounted) return;
  await _initPlayer(newIndex); // _initPlayer এর ভেতরে অলরেডি পজিশন চেক লজিক আছে
}



  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_isLocked) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    if (_isLocked) return;
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  void _togglePlayPause() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() {
      _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
    });
    _startHideTimer();
  }

  void _toggleZoom() {
  setState(() {
    _zoomStep = (_zoomStep + 1) % 3; 
    
    double scale;
    if (_zoomStep == 1) {
      scale = 0.5; 
    } else if (_zoomStep == 2) {
      scale = 1.5; 
    } else {
      scale = 1.0; 
    }
    
    _transformController.value = Matrix4.identity()..scale(scale);
  });
   }

  @override
  void dispose() {
    // ১. ডিসপোজ হওয়ার ঠিক আগে পজিশন সেভ করা
    // যেহেতু dispose মেথডটি async না, তাই SharedPreferences কে সরাসরি কল করা নিরাপদ
    if (_controller != null && _controller!.value.isInitialized) {
      final String videoId = widget.videoAssets[currentIndex].id;
      final int positionMs = _controller!.value.position.inMilliseconds;
      
      // async ছাড়াই SharedPreferences-এ পজিশন পাঠানোর চেষ্টা
      SharedPreferences.getInstance().then((prefs) {
        prefs.setInt('video_pos_$videoId', positionMs);
      });
    }

    // ২. অন্যান্য রিসোর্স রিলিজ করা
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    _nextController?.dispose();
    _prevController?.dispose();
    _transformController.dispose();
    
    // সিস্টেম সেটিংস আগের অবস্থায় ফিরিয়ে আনা
    VolumeController().showSystemUI = true;
    super.dispose();
  }

  // ভিডিওর সময় সুন্দরভাবে দেখানোর মেথড
  String _formatDuration(Duration position) {
    final hours = position.inHours;
    final minutes = position.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = position.inSeconds.remainder(60).toString().padLeft(2, '0');

    if (hours > 0) {
      return "$hours:$minutes:$seconds";
    }
    return "$minutes:$seconds";
  }

  // ইউজার যখন ম্যানুয়ালি ব্যাক বাটন প্রেস করবে (নতুন Async ভার্সন)
  void _onBack() async {
    // ব্যাক হওয়ার আগেই পজিশন সেভ করে রাখা নিরাপদ
    if (_controller != null && _controller!.value.isInitialized) {
      await VideoStorage.savePosition(
        widget.videoAssets[currentIndex].id,
        _controller!.value.position,
      );
    }

    // স্ক্রিন ও সিস্টেম সেটিংস রিসেট
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    ScreenBrightness().resetScreenBrightness().catchError((e) => debugPrint(e.toString()));
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // ব্যাকগ্রাউন্ড প্লে লজিক
    if (_isBackgroundMode && _controller != null && _controller!.value.isInitialized) {
      final currentPosition = _controller!.value.position;
      await audioHandler.seek(currentPosition);
      audioHandler.play();
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

 @override
void didChangeAppLifecycleState(AppLifecycleState state) async {
  // যদি ব্যাকগ্রাউন্ড মোড অফ থাকে বা কন্ট্রোলার না থাকে তবে কিছুই করবে না
  if (!_isBackgroundMode || _controller == null) return;

  if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
    // ১. অ্যাপ যখন ব্যাকগ্রাউন্ডে যাচ্ছে
    if (_controller!.value.isPlaying) {
      final currentPos = _controller!.value.position;
      // অডিও হ্যান্ডলারে বর্তমান পজিশন সেট করে প্লে করা শুরু করুন
      await audioHandler.seek(currentPos);
      await audioHandler.play();
    }
  } 
  else if (state == AppLifecycleState.resumed) {
    // ২. অ্যাপ যখন আবার সামনে আসবে (Foreground)
    final mediaItem = audioHandler.mediaItem.value;
    final audioPos = audioHandler.playbackState.value.position;

    if (mediaItem != null) {
      // চেক করুন ব্যাকগ্রাউন্ডে ভিডিও চেঞ্জ হয়েছে কি না (ID দিয়ে)
      int updatedIndex = widget.videoAssets.indexWhere((v) => v.id == mediaItem.id);

      if (updatedIndex != -1 && updatedIndex != currentIndex) {
        // ভিডিও পাল্টে গেছে! নতুন ভিডিও লোড করতে হবে
        setState(() {
          currentIndex = updatedIndex;
          _isInitializing = true;
        });

        await _controller?.dispose();
        final File? file = await widget.videoAssets[currentIndex].file;
        
        if (file != null) {
          _controller = VideoPlayerController.file(file);
          await _controller!.initialize();
          _controller!.addListener(_videoListener);
          _setOrientation();
        }
      }

      // ভিডিওর সঠিক সময়ে নিয়ে যান এবং অডিও সার্ভিস বন্ধ করুন
      await _controller?.seekTo(audioPos);
      await _controller?.play();
      await audioHandler.stop();
      
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }
}

Future<void> _syncWithAudioHandler() async {
  final mediaItem = audioHandler.mediaItem.value;
  final audioPos = audioHandler.playbackState.value.position;

  if (mediaItem != null) {
    // অডিও হ্যান্ডলারের আইডি অনুযায়ী আপনার লিস্টের ইনডেক্স বের করুন
    int updatedIndex = widget.videoAssets.indexWhere((v) => v.id == mediaItem.id);

    // যদি আইডি না মেলে তবে টাইটেল দিয়ে ট্রাই করুন
    if (updatedIndex == -1) {
      updatedIndex = widget.videoAssets.indexWhere((v) => v.title == mediaItem.title);
    }

    if (updatedIndex != -1) {
      if (updatedIndex != currentIndex) {
        // ব্যাকগ্রাউন্ডে ভিডিও পাল্টে গেছে, তাই নতুন কন্ট্রোলার সেট করুন
        await _controller?.dispose();
        currentIndex = updatedIndex;
        
        final File? file = await widget.videoAssets[currentIndex].file;
        if (file != null) {
          _controller = VideoPlayerController.file(file);
          await _controller!.initialize();
          _controller!.addListener(_videoListener);
          _setOrientation();
        }
      }

      // ভিডিও সঠিক সময়ে নিয়ে প্লে করুন এবং অডিও সার্ভিস থামান
      await _controller?.seekTo(audioPos);
      _controller?.play();
      await audioHandler.stop();
      
      if (mounted) setState(() {});
    }
  }
}

  @override
Widget build(BuildContext context) {
  if (_isInitializing || _controller == null || !_controller!.value.isInitialized) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }

  return PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) return;
      _onBack();
    },
    child: Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        // ১. সিঙ্গেল ট্যাপ: কন্ট্রোলস দেখানো বা লুকানো
        onTapDown: (details) {
          final size = MediaQuery.of(context).size;
          // স্লাইডার এরিয়াতে ক্লিক করলে কন্ট্রোলস হাইড হবে না
          if (_showControls && _isBottomArea(details.localPosition, size)) {
            return; 
          }
          _toggleControls();
        },

        // ২. লং প্রেস: ভিডিওর স্পিড কমানো বা বাড়ানো (0.5x / 2x)
        onLongPressStart: (details) async {
          final size = MediaQuery.of(context).size;
          // লক থাকলে বা স্লাইডার এরিয়াতে টাচ করলে স্পিড কাজ করবে না
          if (_isLocked || _controller == null || (_showControls && _isBottomArea(details.localPosition, size))) {
            return;
          }

          final width = MediaQuery.of(context).size.width;
          final xPos = details.globalPosition.dx;
          if (xPos < width / 2) {
            await _controller!.setPlaybackSpeed(0.5);
            setState(() => _isSlowingDown = true);
          } else {
            await _controller!.setPlaybackSpeed(2.0);
            setState(() => _isFastForwarding = true);
          }
          HapticFeedback.lightImpact();
        },

        onLongPressEnd: (details) async {
          if (_isLocked || _controller == null) return;
          await _controller!.setPlaybackSpeed(1.0);
          setState(() {
            _isFastForwarding = false;
            _isSlowingDown = false;
          });
        },

        // ৩. ডাবল ট্যাপ: পজ এবং ১০ সেকেন্ড আগে/পিছে টানা
        onDoubleTapDown: (details) {
          final size = MediaQuery.of(context).size;
          // লক থাকলে বা স্লাইডার এরিয়াতে ডাবল ট্যাপ করলে কাজ করবে না
          if (_isLocked || (_showControls && _isBottomArea(details.localPosition, size))) {
            return;
          }

          final width = MediaQuery.of(context).size.width;
          final xPos = details.globalPosition.dx;

          // মাঝখানে ডাবল ট্যাপ (Play/Pause)
          if (xPos > width * 0.35 && xPos < width * 0.65) {
            _togglePlayPause();
          } 
          // বামে ডাবল ট্যাপ (Rewind 10s)
          else if (xPos < width * 0.35) {
            final current = _controller!.value.position;
            Duration newPos = current - const Duration(seconds: 10);
            if (newPos < Duration.zero) newPos = Duration.zero;
            _controller!.seekTo(newPos);
            setState(() => _showRewindAnim = true);
            Future.delayed(const Duration(milliseconds: 600), () {
              setState(() => _showRewindAnim = false);
            });
          } 
          // ডানে ডাবল ট্যাপ (Forward 10s)
          else {
            final current = _controller!.value.position;
            Duration newPos = current + const Duration(seconds: 10);
            if (newPos > _controller!.value.duration) newPos = _controller!.value.duration;
            _controller!.seekTo(newPos);
            setState(() => _showForwardAnim = true);
            Future.delayed(const Duration(milliseconds: 600), () {
              setState(() => _showForwardAnim = false);
            });
          }
        },

        // ৪. হরাইজন্টাল ড্র্যাগ: ভিডিও টানা (Seek)
        onHorizontalDragUpdate: (details) {
          final size = MediaQuery.of(context).size;
          // স্লাইডার এরিয়া ব্লক করা হয়েছে
          if (_showControls && _isBottomArea(details.localPosition, size)) return;
          
          if (_isLocked || _controller == null || !_controller!.value.isInitialized) return;

          double sensitivity = 0.2;
          int secondsToMove = (details.delta.dx * sensitivity).toInt();
          final currentPosition = _controller!.value.position;
          final newPos = currentPosition + Duration(seconds: secondsToMove);
          
          if (newPos >= Duration.zero && newPos <= _controller!.value.duration) {
            _controller!.seekTo(newPos);
            setState(() {
              _showSeekIndicator = true;
              _seekTimeText = _formatDuration(newPos);
            });
          }
        },

        onHorizontalDragEnd: (_) async {
          setState(() => _showSeekIndicator = false);
          if (_controller != null && !_controller!.value.isPlaying) {
             await _controller!.play();
          }
        },

        // ৫. ভার্টিকাল ড্র্যাগ: ব্রাইটনেস এবং সাউন্ড কন্ট্রোল
       onVerticalDragUpdate: (details) async {
  final size = MediaQuery.of(context).size;
  if (_showControls && _isBottomArea(details.localPosition, size)) return;
  
  if (_isLocked) return;
  final width = MediaQuery.of(context).size.width;

  if (details.globalPosition.dx < width / 2) {
    // ব্রাইটনেস কন্ট্রোল
    _showBrightness = true;
    _brightness = (_brightness - details.delta.dy / 300).clamp(0.0, 1.0);
    try { 
      await ScreenBrightness().setScreenBrightness(_brightness); 
    } catch (e) { 
      debugPrint("Brightness Error: $e"); 
    }
  } else {
    // সাউন্ড কন্ট্রোল
    _showVolume = true;
    _volume = (_volume - details.delta.dy / 300).clamp(0.0, 1.0);
    VolumeController().setVolume(_volume);
  }
  if (mounted) setState(() {});
},

        onVerticalDragEnd: (_) => setState(() => _showBrightness = _showVolume = false),

        child: Stack(
          children: [
            // ভিডিও ডিসপ্লে (InteractiveViewer দিয়ে জুম সাপোর্ট)
            InteractiveViewer(
              transformationController: _transformController,
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              minScale: 1.0,
              maxScale: 5.0,
              scaleEnabled: !_isLocked,
              panEnabled: !_isLocked,
              child: SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller!.value.size.width,
                    height: _controller!.value.size.height,
                    child: VideoPlayer(_controller!),
                  ),
                ),
              ),
            ),

            if (_isSlowingDown)
  Align(
    // আগের alignment: Alignment.topLeft সরিয়ে এটি বসান:
    alignment: const Alignment(-0.8, -0.4), // বাম দিকের মাঝামাঝি এবং সামান্য ওপরে
    child: AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: _isSlowingDown ? 1.0 : 0.0,
      child: Padding(
        padding: const EdgeInsets.all(0), // আগের Padding সরিয়ে ০ করে দিন
        child: _buildSpeedIndicator("0.5X Slow", Icons.slow_motion_video),
      ),
    ),
  ),

// --- ২. ফাস্ট ইন্ডিকেটর (ডান পাশে মাঝামাঝি) ---
if (_isFastForwarding)
  Align(
    // আগের alignment: Alignment.topRight সরিয়ে এটি বসান:
    alignment: const Alignment(0.8, -0.4), // ডান দিকের মাঝামাঝি এবং সামান্য ওপরে
    child: AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: _isFastForwarding ? 1.0 : 0.0,
      // পুরো কন্টেইনারটি সরিয়ে শুধু '_buildSpeedIndicator' ব্যবহার করুন
      child: _buildSpeedIndicator("2X Fast", Icons.bolt), // আইকন বোল্ট ব্যবহার করা হয়েছে
    ),
  ),

            // ব্রাইটনেস এবং ভলিউম স্লাইডার (Side)
            if (_showBrightness)
  Align(
    alignment: const Alignment(-0.9, 0.0), // -0.9 মানে বামে, 0.0 মানে একদম মাঝে
    child: _buildSideSlider(Icons.brightness_6, _brightness),
  ),

// ভলিউম স্লাইডার (ডান পাশে মাঝে)
if (_showVolume)
  Align(
    alignment: const Alignment(0.9, 0.0), // 0.9 মানে ডানে, 0.0 মানে একদম মাঝে
    child: _buildSideSlider(_volume == 0 ? Icons.volume_off : Icons.volume_up, _volume),
  ),

            // ১০ সেকেন্ড ফরওয়ার্ড/রিওয়াইন্ড এনিমেশন
            if (_showRewindAnim) _buildSmallTapAnim(true),
            if (_showForwardAnim) _buildSmallTapAnim(false),

            // লক বাটন (যখন স্ক্রিন লক থাকে)
            if (_isLocked)
              Positioned(
                top: 40,
                left: 20,
                child: IconButton(
                  icon: const Icon(Icons.lock, color: Colors.white, size: 35),
                  onPressed: () {
                    setState(() {
                      _isLocked = false;
                      _showControls = true;
                    });
                    _startHideTimer();
                  },
                ),
              ),

            // মেইন কন্ট্রোলস (স্লাইডার, প্লে/পজ বাটন ইত্যাদি)
            if (!_isLocked && _showControls) _buildMainControls(),

            // সিক ইন্ডিকেটর (ভিডিও টানলে সময়ের লেখা দেখাবে)
            if (_showSeekIndicator)
              Positioned(
                bottom: 120,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
                    child: Text(_seekTimeText, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}


  Widget _buildSpeedIndicator(String text, IconData icon) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(0.8), // হালকা স্বচ্ছ কালো
      borderRadius: BorderRadius.circular(20), // গোল গোল কোনা
      border: Border.all(color: Colors.white12, width: 1), // খুব হালকা বর্ডার
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.3), // হালকা শ্যাডো
          blurRadius: 8,
          spreadRadius: 2,
          offset: const Offset(0, 4), // নিচের দিকে শ্যাডো
        )
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.orange, size: 20), // আইকনের কালার অরেঞ্জ করা হয়েছে
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15, // টেক্সট সাইজ সামান্য বড় করা হয়েছে
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5
          ),
        ),
      ],
    ),
  );
}

  Widget _buildSideSlider(IconData icon, double value) {
  return UnconstrainedBox( // এটি এরর আসা বন্ধ করবে
    child: Container(
      width: 45, // কন্টেইনারের চওড়া নির্দিষ্ট করা হলো
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black45, // হালকা কালো ব্যাকগ্রাউন্ড
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, // যতটুকু দরকার ততটুকুই জায়গা নিবে
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(height: 8),
          Container(
            height: 100, // স্লাইডারটির উচ্চতা ফিক্সড ১০০ পিক্সেল রাখা হয়েছে
            width: 3,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                FractionallySizedBox(
                  heightFactor: value.clamp(0.0, 1.0),
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "${(value * 100).toInt()}%",
            style: const TextStyle(
              color: Colors.white, 
              fontSize: 10, 
              fontWeight: FontWeight.bold
            ),
          ),
        ],
      ),
    ),
  );
}

 Widget _buildMainControls() {
  return Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.black54, Colors.transparent, Colors.transparent, Colors.black54],
      ),
    ),
    child: Column(
      children: [
        // --- উপরের অংশ: টাইটেল এবং এক্সট্রা মেনু ---
        SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => _onBack(), // আপনার কাস্টম ব্যাক ফাংশন
                  ),
                  Expanded(
                    child: Text(
                      widget.videoAssets[currentIndex].title ?? "Video",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              // --- স্লাইড মেনু (Headphones/Loop) ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _isExtraMenuOpen = !_isExtraMenuOpen),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _isExtraMenuOpen ? Icons.arrow_back_ios_new : Icons.arrow_forward_ios,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        height: 50,
                        margin: const EdgeInsets.only(left: 10),
                        child: _isExtraMenuOpen 
                          ? SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildResponsiveButton(
                                    icon: _isBackgroundMode ? Icons.headphones : Icons.headphones_outlined,
                                    size: 26,
                                    padding: 12,
                                    isActive: _isBackgroundMode,
                                    onPressed: () => setState(() => _isBackgroundMode = !_isBackgroundMode),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildResponsiveButton(
                                    icon: _loopMode == 0 ? Icons.repeat : (_loopMode == 1 ? Icons.repeat_one : Icons.repeat),
                                    size: 26,
                                    padding: 12,
                                    isActive: _loopMode != 0,
                                    onPressed: () => setState(() => _loopMode = (_loopMode + 1) % 3),
                                  ),
                                ],
                              ),
                            ) 
                          : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const Spacer(),

        // --- নিচের অংশ: স্লাইডার এবং মেইন কন্ট্রোলস (সুরক্ষিত এরিয়া) ---
        GestureDetector(
  onTap: () {}, 
  onDoubleTap: () {}, 
  onLongPress: () {}, 
  behavior: HitTestBehavior.opaque, 
  child: Container(
    padding: const EdgeInsets.only(bottom: 5, left: 10, right: 10, top: 0),
    child: Column(
      mainAxisSize: MainAxisSize.min, // এটি কলমটিকে ছোট রাখবে
      children: [
        Row(
          children: [
            Text(_formatDuration(_controller!.value.position), style: const TextStyle(color: Colors.white, fontSize: 11)),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.0,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                ),
                child: Slider(
                  activeColor: Colors.yellow,
                  inactiveColor: Colors.white30,
                  value: _controller!.value.position.inSeconds.toDouble().clamp(0, _controller!.value.duration.inSeconds.toDouble()),
                  max: (_controller!.value.duration.inSeconds == 0 ? 1 : _controller!.value.duration.inSeconds).toDouble(),
                  onChanged: (v) {
                    final destination = Duration(seconds: v.toInt());
                    _controller!.seekTo(destination);
                    if (mounted) setState(() {});
                    _startHideTimer();
                  },
                ),
              ),
            ),
            Text(_formatDuration(_controller!.value.duration), style: const TextStyle(color: Colors.white, fontSize: 11)),
          ],
        ),
                // বাটন কন্ট্রোলস
                LayoutBuilder(
                  builder: (context, constraints) {
                    double totalWidth = constraints.maxWidth;
                    bool isSmall = totalWidth < 350;
                    double sideIconSize = isSmall ? 22 : 28;
                    double navIconSize = isSmall ? 35 : 45;
                    double playIconSize = isSmall ? 55 : 68;

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: Icon(Icons.lock_open_outlined, color: Colors.white, size: sideIconSize),
                          onPressed: () {
                            setState(() {
                              _isLocked = true;
                              _showControls = false;
                            });
                          },
                        ),
                        Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    IconButton(
      icon: Icon(Icons.skip_previous_outlined,
          color: Colors.white,
          size: navIconSize),
      onPressed: currentIndex > 0
          ? () => _changeVideo(currentIndex - 1)
          : null,
    ),

    SizedBox(width: 45), // 👈 gap বাড়াও (20/30/40 যেটা চাই)

    IconButton(
      icon: Icon(
        _controller!.value.isPlaying
            ? Icons.pause_circle_outline
            : Icons.play_circle_outline,
        color: Colors.white,
        size: playIconSize,
      ),
      onPressed: () {
        _togglePlayPause();
        _startHideTimer();
      },
    ),

    SizedBox(width: 45), // 👈 gap

    IconButton(
      icon: Icon(Icons.skip_next_outlined,
          color: Colors.white,
          size: navIconSize),
      onPressed: currentIndex < widget.videoAssets.length - 1
          ? () => _changeVideo(currentIndex + 1)
          : null,
    ),
  ],
),
                        IconButton(
                          icon: Icon(
                            _zoomStep == 1 ? Icons.zoom_out_map_outlined : (_zoomStep == 2 ? Icons.zoom_in_outlined : Icons.fullscreen_outlined),
                            color: Colors.white,
                            size: sideIconSize,
                          ),
                          onPressed: () {
                            _toggleZoom();
                            _startHideTimer();
                          },
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}


  Widget _buildSmallTapAnim(bool isLeft) {
    return Align(
      alignment: isLeft ? const Alignment(-0.6, 0) : const Alignment(0.6, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isLeft ? Icons.fast_rewind : Icons.fast_forward, color: Colors.white, size: 35),
            const Text("10s", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
 
 Widget _buildResponsiveButton({
  required IconData icon,
  required double size,
  required double padding,
  Color iconColor = Colors.white,
  bool isActive = false, 
  VoidCallback? onPressed,
  }) {
  return GestureDetector(
    onTap: onPressed, 
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200), 
      padding: EdgeInsets.symmetric(horizontal: padding / 2, vertical: padding / 2),
      decoration: BoxDecoration(
        color: isActive ? Colors.white.withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(10), 
      ),
      child: Icon(
        icon,
        color: isActive ? Colors.orange : iconColor,
        size: size,
      ),
    ),
  );
 }
}
