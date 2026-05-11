import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'my_audio_handler.dart';
import 'main.dart';

class VideoPlayerPage extends StatefulWidget {
  final List videoAssets;
  final List cachedPaths;
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
  static const String positionKeyPrefix = 'video_pos';

  static Future<void> markAsWatched(String id) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> watched = prefs.getStringList(_key) ?? [];
    if (!watched.contains(id)) {
      watched.add(id);
      await prefs.setStringList(_key, watched);
    }
  }

  static Future<void> savePosition(String id, Duration position) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$positionKeyPrefix$id', position.inMilliseconds);
  }

  static Future<Duration> getPosition(String id) async {
    final prefs = await SharedPreferences.getInstance();
    int? ms = prefs.getInt('$positionKeyPrefix$id');
    return ms != null ? Duration(milliseconds: ms) : Duration.zero;
  }
}

class _VideoPlayerPageState extends State<VideoPlayerPage> with WidgetsBindingObserver {
  late final Player player = Player();
  late final VideoController controller = VideoController(player);

  late int currentIndex;
  bool _isLocked = false;
  bool _showControls = true;
  double _brightness = 0.5;
  double _volume = 0.5;
  double? _draggingValue; 
  bool _showBrightness = false;
  bool _showVolume = false;
  bool _showSeekIndicator = false;
  String _seekTimeText = "";
  bool _showRewindAnim = false;
  bool _showForwardAnim = false;
  Timer? _hideTimer;
  bool _isSwitching = false;
  bool _isFastForwarding = false;
  bool _isSlowingDown = false;
  int _loopMode = 0; // 0: None, 1: Single, 2: All
  bool _isBackgroundMode = false;
  BoxFit _videoFit = BoxFit.contain;
  

  final Map<int, String> _preloadedPaths = {};

  late final StreamSubscription _posSub;
  late final StreamSubscription _completedSub;

  @override
void initState() {
  super.initState();
  // স্ট্যাটাস বার এবং নেভিগেশন বার পুরোপুরি লুকিয়ে ফেলার জন্য
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  
  WidgetsBinding.instance.addObserver(this);
  currentIndex = widget.index;
  VolumeController.instance.showSystemUI = false;
  _initPlayer();
}

  Future<void> _initPlayer() async {
    _posSub = player.stream.position.listen((p) => setState(() {}));
    _completedSub = player.stream.completed.listen((completed) {
      if (completed) _handleVideoEnd();
    });

    await _loadVideo(currentIndex);

    try {
      _brightness = await ScreenBrightness().current;
      _volume = await VolumeController.instance.getVolume();
    } catch (_) {}
    
    _startHideTimer();
  }

  Future<void> _loadVideo(int index) async {
  try {
    final video = widget.videoAssets[index];
    final String videoId = video.id.toString();

    // ১. ভিডিওটি দেখা হয়েছে হিসেবে মার্ক করা (ব্যাকগ্রাউন্ডে হতে পারে)
    VideoStorage.markAsWatched(videoId);

    // ২. পাথ চেক করা (প্রিলোড ম্যাপ থেকে অথবা ফাইল থেকে)
    String? path = _preloadedPaths[index];
    if (path == null) {
      final File? file = await video.file;
      path = file?.path;
      if (path != null) {
        _preloadedPaths[index] = path;
      }
    }

    if (path == null || path.isEmpty) {
      debugPrint("Video path not found");
      return;
    }

    // ৩. সেভ করা পজিশন আগেভাগেই নিয়ে আসা (ওপেন করার সময় কাজে লাগবে)
    Duration savedPosition = await VideoStorage.getPosition(videoId);

    // ৪. মিডিয়া ওপেন করা
    // এখানে play: true দিলে এবং সাথে সাথে seek করলে লোডিং ছাড়াই ভিডিও শুরু হয়
    await player.open(
      Media(path),
      play: true, // সরাসরি প্লে মোডে ওপেন করুন
    );

    // ৫. ভিডিওর ডিউরেশন অনুযায়ী সিক করা
    // player.stream.duration এর জন্য অপেক্ষা করা ভালো যেন সঠিক লেন্থ পাওয়া যায়
    final totalDuration = player.state.duration;
    
    if (savedPosition > Duration.zero) {
      // যদি সেভ করা পজিশন ভিডিওর মোট দৈর্ঘ্যের চেয়ে বড় না হয় তবেই সিক করুন
      if (totalDuration == Duration.zero || savedPosition < totalDuration) {
        await player.seek(savedPosition);
      } else {
        await player.seek(Duration.zero);
      }
    }

    // ৬. অরিয়েন্টেশন সেট করা (ভিডিওর সাইজ পাওয়ার পর)
    player.stream.width.first.then((_) {
      if (mounted) {
        _setOrientation();
      }
    });

    // ৭. পরবর্তী ভিডিও প্রিলোড এবং অডিও হ্যান্ডলার আপডেট করা
    _preloadFiles(index);
    _updateAudioHandler(index);

        if (mounted) {
      setState(() {}); 
    }


  } catch (e, stackTrace) {
    debugPrint("Load Video Error: $e");
    debugPrintStack(stackTrace: stackTrace);
  }
}



Future<void> _preloadFiles(int index) async {
  // পরের এবং আগের ভিডিওর ইনডেক্স বের করা
  int next = index + 1;
  int prev = index - 1;

  // পরের ভিডিওর ফাইল পাথ আগে থেকেই বের করে রাখা
  if (next < widget.videoAssets.length && !_preloadedPaths.containsKey(next)) {
    final file = await widget.videoAssets[next].file;
    if (file != null) _preloadedPaths[next] = file.path;
  }

  // আগের ভিডিওর ফাইল পাথ আগে থেকেই বের করে রাখা
  if (prev >= 0 && !_preloadedPaths.containsKey(prev)) {
    final file = await widget.videoAssets[prev].file;
    if (file != null) _preloadedPaths[prev] = file.path;
  }
}

// আলাদা ফাংশন যাতে ভিডিও চলতে দেরি না হয়
void _updateAudioHandler(int index) async {
  try {
    final List<String> titles = widget.videoAssets.map((v) => v.title.toString()).toList();
    final List<String> ids = widget.videoAssets.map((v) => v.id.toString()).toList();
    
    // শুধু বর্তমান ভিডিওর পাথ দিয়ে আপাতত আপডেট করুন
    final File? currentFile = await widget.videoAssets[index].file;
    if (currentFile != null) {
      await audioHandler.setPlaylist(
        [currentFile.path], 
        0, 
        titles, 
        ids, 
        shouldPlay: false
      );
    }
  } catch (e) {
    debugPrint("AudioHandler Error: $e");
  }
}

  void _setOrientation() {
  final width = player.state.width ?? 0;
  final height = player.state.height ?? 0;

  if (width == 0 || height == 0) return;

  if (height > width) {
    // যদি ভিডিওটি লম্বা (Portrait) হয়
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  } else {
    // যদি ভিডিওটি আড়াআড়ি (Landscape) হয়
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
}

  void _handleVideoEnd() {
    if (_loopMode == 1) {
      player.seek(Duration.zero);
      player.play();
    } else if (_loopMode == 2) {
      _changeVideo((currentIndex + 1) % widget.videoAssets.length);
    } else {
      if (currentIndex < widget.videoAssets.length - 1) {
        _changeVideo(currentIndex + 1);
      }
    }
  }

 void _changeVideo(int newIndex) async {
  // ১. ইন্ডেক্স চেক এবং অলরেডি সুইচ হচ্ছে কি না তা যাচাই
  if (newIndex < 0 || newIndex >= widget.videoAssets.length || _isSwitching) return;

  // ২. ফ্ল্যাগ অন করা (কিন্তু এটি UI-তে কোনো লোডার দেখাবে না যদি আপনি build থেকে loader টি মুছে দেন)
  _isSwitching = true; 

  try {
    // ৩. বর্তমান ভিডিওর পজিশন সেভ করা
    await VideoStorage.savePosition(
      widget.videoAssets[currentIndex].id,
      player.state.position,
    );

    // ৪. ইন্ডেক্স আপডেট এবং স্টেট রিফ্রেশ (কন্ট্রোলস বা টাইটেল আপডেটের জন্য)
    setState(() {
      currentIndex = newIndex;
      // এখানে fast forward বা slow down রিসেট করে দেওয়া ভালো
      _isFastForwarding = false;
      _isSlowingDown = false;
    });

    // ৫. নতুন ভিডিও লোড করা (আপনার প্রিলোড লজিক অনুযায়ী এটি দ্রুত হবে)
    await _loadVideo(newIndex);

  } catch (e) {
    debugPrint("Error switching video: $e");
  } finally {
    // ৬. কাজ শেষ হলে ফ্ল্যাগ অফ করা যাতে ইউজার আবার নেক্সট/প্রিভ বাটন চাপতে পারে
    if (mounted) {
      setState(() {
        _isSwitching = false;
      });
    }
  }
}

  void _startHideTimer() {
  _hideTimer?.cancel(); 
  _hideTimer = Timer(const Duration(seconds: 4), () {
    if (mounted && !_isLocked && _draggingValue == null) {
      setState(() {
        _showControls = false;
      });
    } else if (mounted && _draggingValue != null) {
      _startHideTimer();
    }
  });
}

  void _toggleControls() {
    if (_isLocked) return;
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  @override
void dispose() {
  // আগের ওরিয়েন্টেশন রিসেট করা
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  
  // স্ট্যাটাস বার এবং নেভিগেশন বার পুনরায় ফিরিয়ে আনা
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual, 
    overlays: SystemUiOverlay.values
  );
  
  VideoStorage.savePosition(widget.videoAssets[currentIndex].id, player.state.position);
  WidgetsBinding.instance.removeObserver(this);
  _hideTimer?.cancel();
  _posSub.cancel();
  _completedSub.cancel();
  player.dispose();
  VolumeController.instance.showSystemUI = true;
  super.dispose();
}

  void _onBack() async {
  // ১. ভিডিও পজিশন সেভ করা
  await VideoStorage.savePosition(widget.videoAssets[currentIndex].id, player.state.position);
  
  // ২. স্ক্রিন সোজা (Portrait) করা
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  
  // ৩. ব্রাইটনেস রিসেট
  ScreenBrightness().resetScreenBrightness();
  
  // ৪. স্ট্যাটাস বার ফিরিয়ে আনা
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  if (_isBackgroundMode && player.state.playing) {
    // ব্যাকগ্রাউন্ড মোড অন থাকলে অডিও চলবে
    await audioHandler.seek(player.state.position);
    audioHandler.play();
  } else {
    await player.pause();
  }

  if (mounted) Navigator.of(context).pop();
}


  @override
Widget build(BuildContext context) {
  return PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _onBack();
    },
    child: Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: (_) => _toggleControls(),
        // লং প্রেস লজিক: ভিডিওর গতি বাড়ানো বা কমানো
        onLongPressStart: (details) {
          if (_isLocked) return;
          final width = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < width / 2) {
            player.setRate(0.5);
            setState(() => _isSlowingDown = true);
          } else {
            player.setRate(2.0);
            setState(() => _isFastForwarding = true);
          }
        },
        onLongPressEnd: (_) {
          player.setRate(1.0);
          setState(() {
            _isFastForwarding = false;
            _isSlowingDown = false;
          });
        },
        // ডাবল ট্যাপ লজিক: রিওয়াইন্ড, প্লে/পজ, ফরওয়ার্ড
       onDoubleTapDown: (details) {
  if (_isLocked) return;
  
  final width = MediaQuery.of(context).size.width;
  final xPos = details.globalPosition.dx;

  // মাঝখানে ডাবল ট্যাপ করলে প্লে/পজ হবে
  if (xPos > width * 0.35 && xPos < width * 0.65) {
    player.playOrPause();
  } 
  // স্ক্রিনের বাম পাশে ডাবল ট্যাপ (Rewind)
  else if (xPos < width * 0.35) {
    player.seek(player.state.position - const Duration(seconds: 10));
    
    setState(() {
      _showRewindAnim = true;
      _showForwardAnim = false; // একসাথে দুইটা এনিমেশন যাতে না চলে
    });

    // ৬০০ মিলিসেকেন্ড পর এনিমেশন বন্ধ হবে
    Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _showRewindAnim = false);
    });
  } 
  // স্ক্রিনের ডান পাশে ডাবল ট্যাপ (Forward)
  else {
    player.seek(player.state.position + const Duration(seconds: 10));
    
    setState(() {
      _showForwardAnim = true;
      _showRewindAnim = false;
    });

    Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _showForwardAnim = false);
    });
  }
},
        // হরিজন্টাল ড্র্যাগ: ভিডিও সিকিং
        onHorizontalDragUpdate: (details) {
          if (_isLocked) return;

          // ড্র্যাগ করার সময় টাইমার রিসেট যেন কন্ট্রোল না হারায়
          _startHideTimer();

          double totalDuration = player.state.duration.inSeconds.toDouble();
          if (totalDuration <= 0) return;

          // বর্তমান পজিশন সেট করা (স্লাইডারের সাথে সিঙ্ক রাখার জন্য)
          double currentPos = _draggingValue ?? player.state.position.inSeconds.toDouble();
          
          // আঙুল কতটুকু সরলো তার ভিত্তিতে নতুন পজিশন (০.২ হলো সেন্সিটিভিটি)
          double newValue = currentPos + (details.delta.dx * 0.2);

          setState(() {
            _draggingValue = newValue.clamp(0.0, totalDuration);
            _showSeekIndicator = true;
            _seekTimeText = _formatDuration(Duration(seconds: _draggingValue!.toInt()));
          });
        },
        
        onHorizontalDragEnd: (_) async {
          if (_isLocked || _draggingValue == null) return;

          // হাত ছেড়ে দিলে কেবল তখনই ভিডিও সিক হবে (এতে ভিডিও আটকাবে না)
          await player.seek(Duration(seconds: _draggingValue!.toInt()));

          // ভিডিও লোড হওয়ার জন্য সামান্য সময় দেওয়া
          await Future.delayed(const Duration(milliseconds: 300));

          if (mounted) {
            setState(() {
              _showSeekIndicator = false;
              _draggingValue = null; // কন্ট্রোল আবার প্লেয়ারকে ফেরত দেওয়া
            });
            _startHideTimer(); // ৪ সেকেন্ডের টাইমার আবার চালু
          }
        },

        // ২. ভার্টিকাল ড্র্যাগ: ব্রাইটনেস ও ভলিউম লজিক (টাইমার সিঙ্কসহ)
        onVerticalDragUpdate: (details) async {
          if (_isLocked) return;
          final width = MediaQuery.of(context).size.width;

          // ড্র্যাগ করার সময় টাইমার রিসেট
          _startHideTimer();

          setState(() {
            if (details.globalPosition.dx < width / 2) {
              // স্ক্রিনের বাম পাশে: ব্রাইটনেস পরিবর্তন
              _showBrightness = true;
              _showVolume = false;
              _brightness = (_brightness - details.delta.dy / 300).clamp(0.0, 1.0);
              ScreenBrightness().setScreenBrightness(_brightness);
            } else {
              // স্ক্রিনের ডান পাশে: ভলিউম পরিবর্তন
              _showVolume = true;
              _showBrightness = false;
              _volume = (_volume - details.delta.dy / 300).clamp(0.0, 1.0);
              VolumeController.instance.setVolume(_volume);
            }
          });
        },
        
        onVerticalDragEnd: (_) {
          setState(() {
            _showBrightness = false;
            _showVolume = false;
          });
          _startHideTimer(); // কাজ শেষে টাইমার চালু
        },

        child: Stack(
          children: [
            // ১. ভিডিও প্লেয়ার লেয়ার
            Center(
              child: Video(
                controller: controller,
                controls: null,
                fill: Colors.black,
                fit: _videoFit,
              ),
            ),

            // ৩. গতি ইন্ডিকেটর (Slow/Fast)
            if (_isSlowingDown)
              Align(
                  alignment: const Alignment(-0.8, -0.4),
                  child: _buildIndicator("0.5X Slow", Icons.slow_motion_video)),
            if (_isFastForwarding)
              Align(
                  alignment: const Alignment(0.8, -0.4),
                  child: _buildIndicator("2X Fast", Icons.bolt)),

            // ৪. ব্রাইটনেস স্লাইডার (ডান পাশে)
            if (_showBrightness)
              Align(
                alignment: const Alignment(0.85, 0.0),
                child: _buildSideSlider(Icons.brightness_6, _brightness),
              ),

            // ৫. ভলিউম স্লাইডার (বাম পাশে)
            if (_showVolume)
              Align(
                alignment: const Alignment(-0.85, 0.0),
                child: _buildSideSlider(Icons.volume_up, _volume),
              ),

            // ৬. ডাবল ট্যাপ অ্যানিমেশন
            _buildTapAnim(true), 
            _buildTapAnim(false),

            // ৭. লক স্ক্রিন বাটন
            if (_isLocked)
              Positioned(
                top: 15,
                left: 10,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _isLocked = false;
                      _showControls = true;
                    });
                    _startHideTimer();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 1),
                    ),
                    child: const Icon(
                      Icons.lock_open_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),

            // ৮. মেইন কন্ট্রোলস (প্লে, পজ, নেক্সট, প্রিভিয়াস, জুম)
            if (!_isLocked && _showControls) _buildMainControls(),

            // ৯. সিক বক্স (ড্র্যাগ করার সময় মাঝখানে সময় দেখাবে)
            if (_showSeekIndicator)
              Positioned(
                  bottom: 120, // আপনার আগের স্লাইডার পজিশন অনুযায়ী অ্যাডজাস্ট করা
                  left: 0,
                  right: 0,
                  child: Center(child: _buildSeekBox())),
          ],
        ),
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
          colors: [Colors.black54, Colors.transparent, Colors.transparent, Colors.black87],
        ),
      ),
      child: Column(
        children: [
          SafeArea(
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: _onBack),
                Expanded(child: Text(widget.videoAssets[currentIndex].title ?? "Video", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                _buildActionBtn(_isBackgroundMode ? Icons.headphones : Icons.headphones_outlined, () => setState(() => _isBackgroundMode = !_isBackgroundMode), _isBackgroundMode),
                _buildActionBtn(_loopMode == 1 ? Icons.repeat_one : Icons.repeat, () => setState(() => _loopMode = (_loopMode + 1) % 3), _loopMode != 0),
              ],
            ),
          ),
          const Spacer(),
          _buildBottomBar(),
        ],
      ),
    );
  }

Widget _buildBottomBar() {
  // ১. বর্তমান পজিশন এবং মোট সময় নির্ধারণ
  double currentPos = _draggingValue ?? player.state.position.inSeconds.toDouble();
  double totalDuration = player.state.duration.inSeconds.toDouble();
  if (totalDuration <= 0) totalDuration = 1.0; 

  return Padding(
    padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 10.0, bottom: 0.0),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // --- ১. প্রোগ্রেস বার (Slider) অংশ ---
        Row(
          children: [
            SizedBox(
              width: 45,
              child: Text(
                _formatDuration(Duration(seconds: currentPos.toInt())), 
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
            
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4.0,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.0),
                  activeTrackColor: Colors.yellow,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.yellow,
                ),
                child: Slider(
                  value: currentPos.clamp(0.0, totalDuration),
                  max: totalDuration,
                  onChangeStart: (v) {
                    _hideTimer?.cancel(); // টানা শুরু করলে টাইমার বন্ধ (হাইড হবে না)
                    setState(() => _draggingValue = v);
                  },
                  onChanged: (v) {
                    _startHideTimer(); // নাড়াচাড়া করলে টাইমার রিসেট হবে
                    setState(() => _draggingValue = v);
                  },
                  onChangeEnd: (v) async {
                    await player.seek(Duration(seconds: v.toInt()));
                    await Future.delayed(const Duration(milliseconds: 300));
                    if (mounted) {
                      setState(() => _draggingValue = null);
                      _startHideTimer(); // টানা শেষ হলে ৪ সেকেন্ড গোনা শুরু হবে
                    }
                  },
                ),
              ),
            ),
            
            SizedBox(
              width: 45,
              child: Text(
                _formatDuration(player.state.duration), 
                style: const TextStyle(color: Colors.white, fontSize: 12),
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),

        const SizedBox(height:0),

        // --- ২. মেইন কন্ট্রোল বাটনগুলো ---
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // লক বাটন
            IconButton(
              icon: const Icon(Icons.lock_outline, color: Colors.white, size: 28), 
              onPressed: () {
                _startHideTimer(); // টাইমার রিসেট
                setState(() { 
                  _isLocked = true; 
                  _showControls = false; 
                });
              },
            ),

            // মাঝখানের বাটনগুলো (প্রিভিয়াস, প্লে/পজ, নেক্সট)
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous, color: Colors.white, size: 35), 
                  onPressed: () {
                    _startHideTimer();
                    _changeVideo(currentIndex - 1);
                  },
                ),
                const SizedBox(width: 20),
                IconButton(
                  icon: Icon(
                    player.state.playing ? Icons.pause_circle_filled : Icons.play_circle_filled, 
                    color: Colors.white, 
                    size: 65,
                  ),
                  onPressed: () {
                    _startHideTimer(); // ক্লিক করলে টাইমার রিসেট
                    player.playOrPause();
                  },
                ),
                const SizedBox(width: 20),
                IconButton(
                  icon: const Icon(Icons.skip_next, color: Colors.white, size: 35), 
                  onPressed: () {
                    _startHideTimer();
                    _changeVideo(currentIndex + 1);
                  },
                ),
              ],
            ),

            // ফুল-স্ক্রিন/জুম বাটন
            IconButton(
              icon: Icon(
                _videoFit == BoxFit.contain ? Icons.fullscreen : Icons.fullscreen_exit,
                color: Colors.white,
                size: 30,
              ),
              onPressed: () {
                _startHideTimer(); // ক্লিক করলে টাইমার রিসেট
                setState(() {
                  _videoFit = (_videoFit == BoxFit.contain) ? BoxFit.cover : BoxFit.contain;
                });
              },
            ),
          ],
        ),
      ],
    ),
  );
}



  // Helper Widgets
  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = d.inHours;
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return hours > 0 ? "$hours:$minutes:$seconds" : "$minutes:$seconds";
  }

  Widget _buildIndicator(String text, IconData icon) => Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: Colors.orange, size: 18), const SizedBox(width: 5), Text(text, style: const TextStyle(color: Colors.white))]));

  Widget _buildSideSlider(IconData icon, double val) {
  return Container(
    width: 35, // বারটি আরও চিকন করা হয়েছে
    height: 140, // বারটি আরও ছোট করা হয়েছে
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
      color: Colors.black45, // হালকা স্বচ্ছ ব্যাকগ্রাউন্ড
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      children: [
        Icon(icon, color: Colors.white, size: 16), // আইকন উপরে
        const SizedBox(height: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: RotatedBox(
              quarterTurns: 3,
              child: LinearProgressIndicator(
                value: val,
                backgroundColor: Colors.white12,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "${(val * 100).toInt()}%", // পারসেন্টেজ নিচে
          style: const TextStyle(
            color: Colors.white, 
            fontSize: 10, 
            fontWeight: FontWeight.bold
          ),
        ),
      ],
    ),
  );
}

  


  Widget _buildActionBtn(IconData icon, VoidCallback tap, bool active) => IconButton(icon: Icon(icon, color: active ? Colors.orange : Colors.white), onPressed: tap);

  Widget _buildSeekBox() => Container(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)), child: Text(_seekTimeText, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)));
  
  Widget _buildTapAnim(bool isLeft) {
    return Align(
      alignment: isLeft ? const Alignment(-0.7, 0) : const Alignment(0.7, 0),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: (isLeft ? _showRewindAnim : _showForwardAnim) ? 1.0 : 0.0,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white10,
            shape: BoxShape.circle,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isLeft ? Icons.fast_rewind : Icons.fast_forward,
                color: Colors.white,
                size: 45,
              ),
              const SizedBox(height: 4),
              const Text(
                "10s",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
 
}