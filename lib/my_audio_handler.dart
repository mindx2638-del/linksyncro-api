import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';

class MyAudioHandler extends BaseAudioHandler {
  final _player = AudioPlayer();

  MyAudioHandler() {
    // প্লেয়ারের স্টেট নোটিফিকেশন বারে পাঠানোর জন্য
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // ভিডিও শেষ হলে অটোমেটিক পরেরটাতে যাওয়ার লজিক
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        skipToNext();
      }
    });
  }

  List<String> playlist = [];
  List<String> videoTitles = [];
  List<String> videoIds = [];
  int currentIndex = 0;

  Future<void> setPlaylist(
    List<String> files, 
    int index, 
    List<String> titles, 
    List<String> ids, 
    {bool shouldPlay = true}
  ) async {
    playlist = files;
    currentIndex = index;
    videoTitles = titles;
    videoIds = ids;
    
    if (playlist.isEmpty) return;
    await _playCurrent(autoStart: shouldPlay);
  }

  Future<void> _playCurrent({bool autoStart = true}) async {
  if (playlist.isEmpty || currentIndex < 0 || currentIndex >= playlist.length) return;
  
  final file = playlist[currentIndex];
  final currentTitle = videoTitles[currentIndex];
  final currentId = videoIds[currentIndex];

  try {
    // ১. ফাইল সেট করার সময় preload: true দিন, এতে ফাইলটি দ্রুত প্লে হওয়ার জন্য প্রস্তুত থাকে
    // এবং ডিকোডিং ল্যাগ কমে যায়।
    final duration = await _player.setFilePath(
      file, 
      preload: true
    );

    // ২. নোটিফিকেশন (MediaItem) আপডেট করুন
    mediaItem.add(MediaItem(
      id: currentId,
      album: "LinkSyncro Pro",
      title: currentTitle,
      duration: duration,
      // থাম্বনেইল হিসেবে ভিডিও ফাইলটিই ব্যবহার করছেন, যা ঠিক আছে
      artUri: Uri.file(file), 
    ));

    // ৩. প্লে বা পজ লজিক
    if (autoStart) {
      // play() করার আগে নিশ্চিত করুন প্লেয়ারটি আইডিয়াল স্টেটে নেই
      await _player.play();
    } else {
      await _player.pause();
    }
  } catch (e, stackTrace) {
    // এরর ট্র্যাকিংয়ের জন্য প্রিন্ট
    debugPrint("Error loading audio: $e");
    debugPrintStack(stackTrace: stackTrace);
  }
}


  @override
  Future<void> seek(Duration position) => _player.seek(position);
  
  @override
  Future<void> play() => _player.play();
  
  @override
  Future<void> pause() => _player.pause();
  
  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    if (currentIndex < playlist.length - 1) {
      currentIndex++;
      await _playCurrent(autoStart: true);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (currentIndex > 0) {
      currentIndex--;
      await _playCurrent(autoStart: true);
    }
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: currentIndex,
    );
  }
}