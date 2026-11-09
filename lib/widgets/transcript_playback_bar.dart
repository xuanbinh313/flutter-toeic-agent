import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

typedef TranscriptPlayback = ({
  Duration position,
  Duration duration,
  bool isPlaying,
});

class TranscriptPlaybackBar extends StatelessWidget {
  const TranscriptPlaybackBar({
    super.key,
    required this.audioAvailable,
    required this.playback,
    required this.canPlay,
    required this.onPlay,
    required this.onSeek,
  });

  final bool audioAvailable;
  final ValueListenable<TranscriptPlayback> playback;
  final bool canPlay;
  final VoidCallback onPlay;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    if (!audioAvailable) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Local audio is not available.',
          style: TextStyle(color: Color(0xffa15c00)),
        ),
      );
    }
    return ValueListenableBuilder<TranscriptPlayback>(
      valueListenable: playback,
      builder: (context, value, _) {
        final maximum = value.duration.inMilliseconds == 0
            ? 1.0
            : value.duration.inMilliseconds.toDouble();
        final current = value.position.inMilliseconds
            .clamp(0, maximum.toInt())
            .toDouble();
        return Row(
          children: [
            IconButton.filled(
              onPressed: canPlay ? onPlay : null,
              icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
            ),
            const SizedBox(width: 8),
            Text(_format(value.position)),
            Expanded(
              child: Slider(
                value: current,
                max: maximum,
                onChanged: (position) =>
                    onSeek(Duration(milliseconds: position.round())),
              ),
            ),
            Text(_format(value.duration)),
          ],
        );
      },
    );
  }

  String _format(Duration value) =>
      (value.inMilliseconds / 1000).toStringAsFixed(2);
}
