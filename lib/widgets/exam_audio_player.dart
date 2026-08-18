import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

class ExamAudioPlayer extends StatefulWidget {
  const ExamAudioPlayer({super.key, required this.audioName});
  final String? audioName;
  @override
  State<ExamAudioPlayer> createState() => _ExamAudioPlayerState();
}

class _ExamAudioPlayerState extends State<ExamAudioPlayer> {
  final _player = AudioPlayer();
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  late final String? _path = _resolvePath(widget.audioName);

  @override
  void initState() {
    super.initState();
    _player.onPositionChanged.listen((value) {
      if (mounted) {
        setState(() => _position = value);
      }
    });
    _player.onDurationChanged.listen((value) {
      if (mounted) {
        setState(() => _duration = value);
      }
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _position = Duration.zero;
        });
      }
    });
  }

  String? _resolvePath(String? filename) {
    if (filename == null || filename.trim().isEmpty) return null;
    final direct = File(filename);
    if (direct.existsSync()) return direct.path;
    final appData = Platform.environment['APPDATA'];
    if (appData == null) return null;
    final path =
        '$appData${Platform.pathSeparator}jun-toeic${Platform.pathSeparator}${filename.split(RegExp(r'[\\/]')).last}';
    return File(path).existsSync() ? path : null;
  }

  Future<void> _toggle() async {
    if (_path == null) return;
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play(DeviceFileSource(_path));
    }
    if (mounted) {
      setState(() => _playing = !_playing);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_path == null) {
      return const Text(
        'No local audio is available for this exam.',
        style: TextStyle(color: Color(0xff52616b)),
      );
    }
    final maximum = _duration.inMilliseconds == 0
        ? 1.0
        : _duration.inMilliseconds.toDouble();
    return Row(
      children: [
        IconButton.filled(
          onPressed: _toggle,
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Slider(
            value: _position.inMilliseconds
                .clamp(0, maximum.toInt())
                .toDouble(),
            max: maximum,
            onChanged: (value) async {
              final position = Duration(milliseconds: value.round());
              await _player.seek(position);
              setState(() => _position = position);
            },
          ),
        ),
        Text('${_format(_position)} / ${_format(_duration)}'),
      ],
    );
  }

  String _format(Duration value) =>
      '${value.inMinutes.remainder(60).toString().padLeft(2, '0')}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}
