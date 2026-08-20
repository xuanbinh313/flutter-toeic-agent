import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../config.dart';
import '../models.dart';
import '../services/audio_segment_detection_service.dart';
import '../services/local_database.dart';
import '../services/transcript_translation_service.dart';
import 'detected_audio_segments_dialog.dart';
import 'transcript_chunk_grid.dart';

class TranscriptTab extends StatefulWidget {
  const TranscriptTab({
    super.key,
    required this.examId,
    required this.audioSource,
  });

  final String examId;
  final String? audioSource;

  @override
  State<TranscriptTab> createState() => _TranscriptTabState();
}

class _TranscriptTabState extends State<TranscriptTab> {
  final _player = AudioPlayer();
  final _playback = ValueNotifier((
    position: Duration.zero,
    duration: Duration.zero,
    isPlaying: false,
  ));
  List<SrtChunk> _chunks = [];
  String? _selectedId;
  ({String chunkId, Duration start, Duration end})? _activePlaybackRange;
  bool _isEndingPlayback = false;
  bool _hasChanges = false;
  bool _isLoaded = false;
  bool _isRepeating = false;
  bool _isDetectingAudio = false;
  bool _isTranslating = false;
  bool _transcriptRefreshQueued = false;
  int _gridRevision = 0;

  @override
  void initState() {
    super.initState();
    _loadChunks();
    _player.onPositionChanged.listen(_onPositionChanged);
    _player.onDurationChanged.listen((value) {
      if (mounted) _updatePlayback(duration: value);
    });
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) _updatePlayback(isPlaying: state == PlayerState.playing);
    });
  }

  Future<void> _loadChunks() async {
    final chunks = await LocalDatabase.instance.loadSrtChunks(widget.examId);
    chunks.sort((a, b) => a.index.compareTo(b.index));
    if (mounted) {
      setState(() {
        _chunks = chunks;
        _isLoaded = true;
      });
    }
  }

  SrtChunk? get _selectedChunk {
    for (final chunk in _chunks) {
      if (chunk.id == _selectedId) return chunk;
    }
    return null;
  }

  String? get _audioPath {
    final source = widget.audioSource;
    if (source == null || source.isEmpty) return null;
    if (File(source).existsSync()) return source;
    final appData = Platform.environment['APPDATA'];
    if (appData == null) return null;
    final name = source.split(RegExp(r'[\\/]')).last;
    final path =
        '$appData${Platform.pathSeparator}jun-toeic${Platform.pathSeparator}$name';
    return File(path).existsSync() ? path : null;
  }

  Future<void> _onPositionChanged(Duration position) async {
    final range = _activePlaybackRange;
    if (range != null && position >= range.end) {
      if (_isEndingPlayback) return;
      _isEndingPlayback = true;
      try {
        if (_isRepeating) {
          await _player.seek(range.start);
          position = range.start;
        } else {
          // Do not seek from a position callback. On Windows that can overlap
          // the pause command while the native player is raising this event.
          position = range.end;
          _updatePlayback(position: position, isPlaying: false);
          await _player.pause();
        }
      } catch (_) {
        // The page may be closing while a native audio operation completes.
      } finally {
        _isEndingPlayback = false;
      }
    }
    if (mounted) _updatePlayback(position: position);
  }

  Future<void> _playSelection() async {
    final chunk = _selectedChunk;
    final path = _audioPath;
    if (chunk == null || path == null) return;
    if (_playback.value.isPlaying) {
      await _player.pause();
    } else {
      final range = (
        chunkId: chunk.id,
        start: Duration(milliseconds: _milliseconds(chunk.start)),
        end: Duration(milliseconds: _milliseconds(chunk.end)),
      );
      _activePlaybackRange = range;
      await _player.play(DeviceFileSource(path), position: range.start);
    }
  }

  double _changeTime(String id, String field, double value) {
    final chunk = _chunks.firstWhere((item) => item.id == id);
    setState(() {
      if (field == 'start') {
        chunk.start = value.clamp(0, chunk.end).toDouble();
      } else {
        chunk.end = value < chunk.start ? chunk.start : value;
      }
      _hasChanges = true;
    });
    return field == 'start' ? chunk.start : chunk.end;
  }

  void _changeTranscript(String id, String text) {
    final chunk = _chunks.firstWhere((item) => item.id == id);
    if (chunk.text == text) return;
    chunk.text = text;
    _hasChanges = true;
    if (_transcriptRefreshQueued) return;
    _transcriptRefreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _transcriptRefreshQueued = false;
      setState(() {});
    });
  }

  Future<void> _runAction(String id, String action) async {
    if (_selectedId != id) setState(() => _selectedId = id);
    switch (action) {
      case 'play':
        await _playSelection();
      case 'repeat':
        setState(() => _isRepeating = !_isRepeating);
      case 'merge':
        _mergeNext();
      case 'duplicate':
        _duplicate();
      case 'split':
        await _showSplitDialog();
      case 'delete':
        _delete();
    }
  }

  void _mergeNext() {
    final chunk = _selectedChunk;
    if (chunk == null) return;
    final index = _chunks.indexOf(chunk);
    if (index == _chunks.length - 1) return;
    setState(() {
      final next = _chunks.removeAt(index + 1);
      chunk.end = next.end;
      chunk.text = '${chunk.text} ${next.text}'.trim();
      chunk.hint = [
        chunk.hint,
        next.hint,
      ].whereType<String>().where((value) => value.isNotEmpty).join('\n');
      _hasChanges = true;
    });
  }

  void _duplicate() {
    final chunk = _selectedChunk;
    if (chunk == null) return;
    final index = _chunks.indexOf(chunk);
    setState(() {
      _chunks.insert(
        index + 1,
        _copyChunk(chunk, start: chunk.start, end: chunk.end),
      );
      _hasChanges = true;
    });
  }

  void _delete() {
    final chunk = _selectedChunk;
    if (chunk == null) return;
    if (_activePlaybackRange?.chunkId == chunk.id) {
      _activePlaybackRange = null;
      _player.stop();
    }
    setState(() {
      _chunks.remove(chunk);
      _selectedId = null;
      _hasChanges = true;
    });
  }

  Future<void> _showSplitDialog() async {
    final chunk = _selectedChunk;
    if (chunk == null) return;
    final controller = TextEditingController(text: chunk.text);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Split at cursor'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final offset = controller.selection.baseOffset;
              if (offset <= 0 || offset >= controller.text.length) return;
              final index = _chunks.indexOf(chunk);
              final end = chunk.end;
              final splitAt = (chunk.start + end) / 2;
              setState(() {
                chunk.text = controller.text.substring(0, offset).trim();
                chunk.end = splitAt;
                _chunks.insert(
                  index + 1,
                  _copyChunk(
                    chunk,
                    start: splitAt,
                    end: end,
                    text: controller.text.substring(offset).trim(),
                  ),
                );
                _hasChanges = true;
              });
              Navigator.pop(context);
            },
            child: const Text('Split'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  SrtChunk _copyChunk(
    SrtChunk source, {
    required double start,
    required double end,
    String? text,
  }) => SrtChunk(
    id: '${DateTime.now().microsecondsSinceEpoch}-${source.id}',
    index: _chunks.indexOf(source) + 2,
    start: start,
    end: end,
    text: text ?? source.text,
    hint: source.hint,
  );

  Future<void> _save() async {
    await LocalDatabase.instance.saveSrtChunks(widget.examId, _chunks);
    if (mounted) setState(() => _hasChanges = false);
  }

  Future<void> _autoDetectAudio() async {
    if (_chunks.isEmpty) {
      _showMessage('No local SRT segments are available for this exam.');
      return;
    }
    if (AppConfig.geminiApiKey.isEmpty) {
      _showMessage('Set GEMINI_API_KEY at build time to auto-detect audio.');
      return;
    }
    setState(() => _isDetectingAudio = true);
    try {
      final contexts = await LocalDatabase.instance.loadExamContexts(
        widget.examId,
      );
      final results = await const AudioSegmentDetectionService().detect(
        chunks: _chunks,
        contexts: contexts,
      );
      if (!mounted) return;
      if (results.isEmpty) {
        _showMessage('No matching audio segments were detected.');
        return;
      }
      final approved = await showDetectedAudioSegmentsDialog(context, results);
      if (approved == null || approved.isEmpty) return;
      for (final segment in approved) {
        await LocalDatabase.instance.updateContextAudioSegment(
          segment.context.id,
          start: segment.start,
          end: segment.end,
        );
      }
      _showMessage('Saved audio segments for ${approved.length} context(s).');
    } on GenerativeAIException catch (error) {
      _showMessage('Audio detection failed: ${error.message}');
    } on FormatException catch (error) {
      _showMessage('Audio detection returned invalid JSON: ${error.message}');
    } catch (error) {
      _showMessage('Audio detection failed: $error');
    } finally {
      if (mounted) setState(() => _isDetectingAudio = false);
    }
  }

  Future<void> _translateToVietnamese() async {
    setState(() => _isTranslating = true);
    try {
      final translatedCount = await const TranscriptTranslationService()
          .translate(_chunks);
      if (translatedCount == 0) {
        _showMessage('No transcript translations were returned.');
        return;
      }
      setState(() {
        _hasChanges = true;
        _gridRevision++;
      });
      await LocalDatabase.instance.saveSrtChunks(widget.examId, _chunks);
      if (mounted) setState(() => _hasChanges = false);
      _showMessage(
        'Translations saved: $translatedCount Note segments updated.',
      );
    } on GenerativeAIException catch (error) {
      _showMessage('Translation agent failed: ${error.message}');
    } on FormatException catch (error) {
      _showMessage('Translation agent returned invalid JSON: ${error.message}');
    } catch (error) {
      _showMessage('Could not translate transcript: $error');
    } finally {
      if (mounted) setState(() => _isTranslating = false);
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  int _milliseconds(double seconds) => (seconds * 1000).round();

  void _updatePlayback({
    Duration? position,
    Duration? duration,
    bool? isPlaying,
  }) {
    final current = _playback.value;
    _playback.value = (
      position: position ?? current.position,
      duration: duration ?? current.duration,
      isPlaying: isPlaying ?? current.isPlaying,
    );
  }

  String _format(Duration value) =>
      (value.inMilliseconds / 1000).toStringAsFixed(2);

  @override
  void dispose() {
    _playback.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        _toolbar(),
        const SizedBox(height: 8),
        if (_audioPath == null) _audioUnavailable() else _progressBar(),
        const SizedBox(height: 8),
        Expanded(
          child: TranscriptChunkGrid(
            key: ValueKey(_gridRevision),
            chunks: _chunks,
            isLoaded: _isLoaded,
            onSelected: (id) => setState(() => _selectedId = id),
            onTimeChanged: _changeTime,
            onTextChanged: _changeTranscript,
            onAction: _runAction,
          ),
        ),
      ],
    );
  }

  Widget _toolbar() => Row(
    children: [
      const Expanded(
        child: Text(
          'Transcript chunks',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
      ),
      OutlinedButton.icon(
        onPressed: _isDetectingAudio ? null : _autoDetectAudio,
        icon: const Icon(Icons.auto_awesome),
        label: Text(
          _isDetectingAudio ? 'Detecting audio...' : 'Auto-detect Audio',
        ),
      ),
      const SizedBox(width: 8),
      OutlinedButton.icon(
        onPressed: _isTranslating ? null : _translateToVietnamese,
        icon: const Icon(Icons.translate),
        label: Text(
          _isTranslating ? 'Translating...' : 'Translate to Vietnamese',
        ),
      ),
      const SizedBox(width: 8),
      OutlinedButton.icon(
        onPressed: _selectedChunk == null ? null : _showSplitDialog,
        icon: const Icon(Icons.call_split),
        label: const Text('Split at cursor'),
      ),
      if (_hasChanges) ...[
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save),
          label: const Text('Save'),
        ),
      ],
    ],
  );

  Widget _audioUnavailable() => const Align(
    alignment: Alignment.centerLeft,
    child: Text(
      'Local audio is not available.',
      style: TextStyle(color: Color(0xffa15c00)),
    ),
  );

  Widget _progressBar() => ValueListenableBuilder(
    valueListenable: _playback,
    builder: (context, playback, _) {
      final maximum = playback.duration.inMilliseconds == 0
          ? 1.0
          : playback.duration.inMilliseconds.toDouble();
      final current = playback.position.inMilliseconds
          .clamp(0, maximum.toInt())
          .toDouble();
      return Row(
        children: [
          IconButton.filled(
            onPressed: _selectedChunk == null ? null : _playSelection,
            icon: Icon(playback.isPlaying ? Icons.pause : Icons.play_arrow),
          ),
          const SizedBox(width: 8),
          Text(_format(playback.position)),
          Expanded(
            child: Slider(
              value: current,
              max: maximum,
              onChanged: (value) {
                final position = Duration(milliseconds: value.round());
                _player.seek(position);
                _updatePlayback(position: position);
              },
            ),
          ),
          Text(_format(playback.duration)),
        ],
      );
    },
  );
}
