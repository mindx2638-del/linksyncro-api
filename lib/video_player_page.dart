import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:photo_manager/photo_manager.dart'; 
import 'package:shared_preferences/shared_preferences.dart';
import 'package:volume_controller/volume_controller.dart';


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
  static const String _positionKeyPrefix = 'video_pos_'; 
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

  static Future<void> savePosition(String id, Duration position) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_positionKeyPrefix$id', position.inMilliseconds);
  }

  static Future<Duration> getPosition(String id) async {
    final prefs = await SharedPreferences.getInstance();
    int? ms = prefs.getInt('$_positionKeyPrefix$id');
    if (ms != null) {
      return Duration(milliseconds: ms);
    }
    return Duration.zero;
  }

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

  @override
  void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this); 
  currentIndex = widget.index; 
  _transformController = TransformationController();
    VolumeController.instance.showSystemUI = false;
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
  final String videoId = widget.videoAssets[index].id;
  await VideoStorage.markAsWatched(videoId);
  _controller?.removeListener(_videoListener);
  await _controller?.dispose();
  _controller = null;
  try {
    final File? file = await widget.videoAssets[index].file;
    if (file != null) {
      _controller = VideoPlayerController.file(file);
      await _controller!.initialize();
      if (!mounted || _controller == null || !_controller!.value.isInitialized) return;
      final Duration savedPosition = await VideoStorage.getPosition(videoId);
      if (savedPosition > Duration.zero && savedPosition < _controller!.value.duration) {
        await _controller!.seekTo(savedPosition);
      }
      _setOrientation();
      _controller!.play();
      await _controller!.setPlaybackSpeed(1.0);
      _controller!.addListener(_videoListener);
      try {
        _brightness = await ScreenBrightness().current;
      } catch (_) {
        _brightness = 0.5;
      }     
      _volume = await VolumeController.instance.getVolume();
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _showSeekIndicator = false;
      });
      _startHideTimer();
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
    if (_loopMode == 1) {
      _controller!.seekTo(Duration.zero).then((_) {
        if (mounted) {
          _controller!.play();
          _controller!.addListener(_videoListener); 
        }
      });
      return;
    }

    if (_loopMode == 2) {
      int nextIndex = (currentIndex + 1) % widget.videoAssets.length;
      _changeVideo(nextIndex);
      return;
    }

    if (currentIndex < widget.videoAssets.length - 1) {
      _changeVideo(currentIndex + 1);
    } else {
      if (mounted) setState(() {}); 
    }
    return; 
  }
  if (mounted) setState(() {});
}

  void _changeVideo(int newIndex) async {
  if (newIndex < 0 || newIndex >= widget.videoAssets.length || !mounted) return;
  if (_controller != null && _controller!.value.isInitialized) {
    final String currentId = widget.videoAssets[currentIndex].id;
    final Duration currentPos = _controller!.value.position;
    await VideoStorage.savePosition(currentId, currentPos);
  }
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

  // ৩. নেক্সট/প্রিভিয়াস সোয়াপ লজিক (আপনার সব লজিক অক্ষুণ্ণ রাখা হয়েছে)
  if (newIndex == currentIndex + 1 && _nextController != null && _nextController!.value.isInitialized) {
    await _prevController?.dispose(); // safe dispose
    _prevController = _controller;
    _controller = _nextController;
    _nextController = null;
    swapped = true;
  } 
  else if (newIndex == currentIndex - 1 && _prevController != null && _prevController!.value.isInitialized) {
    await _nextController?.dispose(); // safe dispose
    _nextController = _controller;
    _controller = _prevController;
    _prevController = null;
    swapped = true;
  }

  if (swapped) {
    _controller!.addListener(_videoListener);
    setState(() {
      currentIndex = newIndex;
      _isInitializing = false;
      _transformController.value = Matrix4.identity();
      _zoomStep = 0;
    });
    final Duration savedPos = await VideoStorage.getPosition(widget.videoAssets[currentIndex].id);
    if (savedPos > Duration.zero && savedPos < _controller!.value.duration) {
      await _controller!.seekTo(savedPos);
    }
    await _controller!.setPlaybackSpeed(1.0);
    _controller!.play();
    _setOrientation();
    _startHideTimer();
    _preloadNextVideo(currentIndex + 1);
    _preloadPrevVideo(currentIndex - 1);
    await VideoStorage.markAsWatched(widget.videoAssets[currentIndex].id);
    return;
  }
  await _disposePreloadControllers(); 
  if (_controller != null) {
    _controller!.removeListener(_videoListener); 
    await _controller!.dispose();
    _controller = null;
  }
  setState(() {
    currentIndex = newIndex;
    _isInitializing = true;
    _transformController.value = Matrix4.identity();
    _zoomStep = 0;
  });
  if (!mounted) return;
  await _initPlayer(newIndex); 
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
  WidgetsBinding.instance.removeObserver(this);
  _hideTimer?.cancel();
  if (_controller != null && _controller!.value.isInitialized) {
    final String videoId = widget.videoAssets[currentIndex].id;
    final int positionMs = _controller!.value.position.inMilliseconds;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt('video_pos_$videoId', positionMs);
    });
  }
  _controller?.removeListener(_videoListener);
  _nextController?.removeListener(_videoListener); 
  _prevController?.removeListener(_videoListener); 
  _controller?.dispose();
  _nextController?.dispose();
  _prevController?.dispose();
  _transformController.dispose();
  VolumeController.instance.showSystemUI = true;
  super.dispose();
}

  String _formatDuration(Duration position) {
    final hours = position.inHours;
    final minutes = position.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = position.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return "$hours:$minutes:$seconds";
    }
    return "$minutes:$seconds";
  }

  void _onBack() async {
    if (_controller != null && _controller!.value.isInitialized) {
      await VideoStorage.savePosition(
        widget.videoAssets[currentIndex].id,
        _controller!.value.position,
      );
    }
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    ScreenBrightness().resetScreenBrightness().catchError((e) => debugPrint(e.toString()));
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) {
      Navigator.of(context).pop();
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
        onTapDown: (details) {
          final size = MediaQuery.of(context).size;
          if (_showControls && _isBottomArea(details.localPosition, size)) {
            return; 
          }
          _toggleControls();
        },
        onLongPressStart: (details) async {
          final size = MediaQuery.of(context).size;
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
        onDoubleTapDown: (details) {
          final size = MediaQuery.of(context).size;
          if (_isLocked || (_showControls && _isBottomArea(details.localPosition, size))) {
            return;
          }
          final width = MediaQuery.of(context).size.width;
          final xPos = details.globalPosition.dx;
          if (xPos > width * 0.35 && xPos < width * 0.65) {
            _togglePlayPause();
          } 
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
        onHorizontalDragUpdate: (details) {
          final size = MediaQuery.of(context).size;
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
       onVerticalDragUpdate: (details) async {
  final size = MediaQuery.of(context).size;
  if (_showControls && _isBottomArea(details.localPosition, size)) return;
  if (_isLocked) return;
  final width = MediaQuery.of(context).size.width;
  if (details.globalPosition.dx < width / 2) {
    _showBrightness = true;
    _brightness = (_brightness - details.delta.dy / 300).clamp(0.0, 1.0);
    try { 
      await ScreenBrightness().setScreenBrightness(_brightness); 
    } catch (e) { 
      debugPrint("Brightness Error: $e"); 
    }
  } else {
    _showVolume = true;
    _volume = (_volume - details.delta.dy / 300).clamp(0.0, 1.0);
    VolumeController.instance.setVolume(_volume);
  }
  if (mounted) setState(() {});
},
        onVerticalDragEnd: (_) => setState(() => _showBrightness = _showVolume = false),
        child: Stack(
          children: [
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
    alignment: const Alignment(-0.8, -0.4), 
    child: AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: _isSlowingDown ? 1.0 : 0.0,
      child: Padding(
        padding: const EdgeInsets.all(0),
        child: _buildSpeedIndicator("0.5X Slow", Icons.slow_motion_video),
      ),
    ),
  ),

if (_isFastForwarding)
  Align(
    alignment: const Alignment(0.8, -0.4), 
    child: AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: _isFastForwarding ? 1.0 : 0.0,
      child: _buildSpeedIndicator("2X Fast", Icons.bolt), 
    ),
  ),

  if (_showBrightness)
  Align(
    alignment: const Alignment(-0.9, 0.0), 
    child: _buildSideSlider(Icons.brightness_6, _brightness),
  ),

if (_showVolume)
  Align(
    alignment: const Alignment(0.9, 0.0),
    child: _buildSideSlider(_volume == 0 ? Icons.volume_off : Icons.volume_up, _volume),
  ),

            if (_showRewindAnim) _buildSmallTapAnim(true),
            if (_showForwardAnim) _buildSmallTapAnim(false),
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
            if (!_isLocked && _showControls) _buildMainControls(),
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
      color: Colors.black.withOpacity(0.8), 
      borderRadius: BorderRadius.circular(20), 
      border: Border.all(color: Colors.white12, width: 1), 
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.3), 
          blurRadius: 8,
          spreadRadius: 2,
          offset: const Offset(0, 4), 
        )
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.orange, size: 20), 
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15, 
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5
          ),
        ),
      ],
    ),
  );
}

  Widget _buildSideSlider(IconData icon, double value) {
  return UnconstrainedBox( 
    child: Container(
      width: 45, 
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black45, 
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, 
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(height: 8),
          Container(
            height: 100, 
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
  Widget _buildCircularBtn({
    required Widget icon,
    required VoidCallback onPressed,
    double size = 45,
    Color bgColor = Colors.white10,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: () {
        _startHideTimer();
        onPressed();
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isActive ? Colors.orange.withOpacity(0.2) : bgColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: isActive ? Colors.orange : Colors.white12,
            width: 1,
          ),
        ),
        child: Center(child: icon),
      ),
    );
  }

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
        SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => _onBack(),
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

                                 /* _buildCircularBtn(
                                    icon: Icon(_isBackgroundMode ? Icons.headphones : Icons.headphones_outlined, 
                                          color: _isBackgroundMode ? Colors.orange : Colors.white, size: 20),
                                    size: 40,
                                    isActive: _isBackgroundMode,
                                    onPressed: () => setState(() => _isBackgroundMode = !_isBackgroundMode),
                                  ),
                                  const SizedBox(width: 10),*/

                                  _buildCircularBtn(
                                    icon: Icon(_loopMode == 1 ? Icons.repeat_one : Icons.repeat, 
                                          color: _loopMode != 0 ? Colors.orange : Colors.white, size: 20),
                                    size: 40,
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
       
        GestureDetector(
          onTap: () {}, 
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.only(bottom: 20, left: 15, right: 15),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(_formatDuration(_controller!.value.position), 
                         style: const TextStyle(color: Colors.white, fontSize: 11)),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2.0,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                          activeTrackColor: Colors.yellow,
                          inactiveTrackColor: Colors.white24,
                        ),
                        child: Slider(
                          value: _controller!.value.position.inSeconds.toDouble()
                                  .clamp(0, _controller!.value.duration.inSeconds.toDouble()),
                          max: (_controller!.value.duration.inSeconds == 0 ? 1 : _controller!.value.duration.inSeconds).toDouble(),
                          onChanged: (v) {
                            _controller!.seekTo(Duration(seconds: v.toInt()));
                            if (mounted) setState(() {});
                            _startHideTimer();
                          },
                        ),
                      ),
                    ),
                    Text(_formatDuration(_controller!.value.duration), 
                         style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ],
                ),               
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    double totalWidth = constraints.maxWidth;
                    bool isSmall = totalWidth < 350;
                    double sideBtnSize = isSmall ? 40 : 45;
                    double navBtnSize = isSmall ? 45 : 50;
                    double playBtnSize = isSmall ? 60 : 70;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // লক বাটন
                        _buildCircularBtn(
                          size: sideBtnSize,
                          icon: const Icon(Icons.lock_open_outlined, color: Colors.white, size: 24),
                          onPressed: () {
                            setState(() {
                              _isLocked = true;
                              _showControls = false;
                            });
                          },
                        ),

                        // মিডিয়া কন্ট্রোল গ্রুপ
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // আগের ভিডিও
                            _buildCircularBtn(
                              size: navBtnSize,
                              icon: const Icon(Icons.skip_previous_outlined, color: Colors.white, size: 30),
                              onPressed: currentIndex > 0 ? () => _changeVideo(currentIndex - 1) : () {},
                            ),                           
                            const SizedBox(width: 25), 
                            _buildCircularBtn(
                              size: playBtnSize,
                              bgColor: Colors.white12, 
                              icon: Icon(
                                _controller!.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: isSmall ? 40 : 50,
                              ),
                              onPressed: _togglePlayPause,
                            ),
                            const SizedBox(width: 25), 
                            _buildCircularBtn(
                              size: navBtnSize,
                              icon: const Icon(Icons.skip_next_outlined, color: Colors.white, size: 30),
                              onPressed: currentIndex < widget.videoAssets.length - 1 
                                          ? () => _changeVideo(currentIndex + 1) : () {},
                            ),
                          ],
                        ),
                        _buildCircularBtn(
                          size: sideBtnSize,
                          icon: Icon(
                            _zoomStep == 1 ? Icons.zoom_out_map_outlined : (_zoomStep == 2 ? Icons.zoom_in_outlined : Icons.fullscreen_outlined),
                            color: Colors.white,
                            size: 24,
                          ),
                          onPressed: _toggleZoom,
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
}
