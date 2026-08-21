import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

class RangeAudioPlayer {
  RangeAudioPlayer({required this.onChanged}) {
    _positionSubscription = _player.onPositionChanged.listen(_atPosition);
  }

  final AudioPlayer _player = AudioPlayer();
  final void Function() onChanged;
  late final StreamSubscription<Duration> _positionSubscription;
  Timer? _endTimer;
  String? _playingId;
  Duration? _end;

  String? get playingId => _playingId;

  Future<void> toggle({
    required String id,
    required String path,
    required double startSeconds,
    required double endSeconds,
  }) async {
    if (_playingId == id) {
      await stop();
      return;
    }
    await stop(notify: false);
    _end = Duration(milliseconds: (endSeconds * 1000).round());
    await _player.play(
      DeviceFileSource(path),
      position: Duration(milliseconds: (startSeconds * 1000).round()),
    );
    _playingId = id;
    _endTimer = Timer(
      Duration(milliseconds: ((endSeconds - startSeconds) * 1000).ceil()),
      stop,
    );
    onChanged();
  }

  void _atPosition(Duration position) {
    final end = _end;
    if (_playingId != null && end != null && position >= end) {
      unawaited(stop());
    }
  }

  Future<void> stop({bool notify = true}) async {
    _endTimer?.cancel();
    _endTimer = null;
    _end = null;
    _playingId = null;
    await _player.stop();
    if (notify) onChanged();
  }

  Future<void> dispose() async {
    _endTimer?.cancel();
    await _positionSubscription.cancel();
    await _player.dispose();
  }
}
