import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models.dart';
import '../services/local_database.dart';
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
  List<SrtChunk> _chunks = [];
  String? _selectedId;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _hasChanges = false;
  bool _isLoaded = false;
  bool _isPlaying = false;
  bool _isRepeating = false;
  bool _isTranslating = false;

  @override
  void initState() {
    super.initState();
    _loadChunks();
    _player.onPositionChanged.listen(_onPositionChanged);
    _player.onDurationChanged.listen((value) {
      if (mounted) setState(() => _duration = value);
    });
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
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

  void _onPositionChanged(Duration position) {
    final chunk = _selectedChunk;
    if (chunk != null && position.inMilliseconds >= _milliseconds(chunk.end)) {
      final end = Duration(milliseconds: _milliseconds(chunk.end));
      if (_isRepeating) {
        final start = Duration(milliseconds: _milliseconds(chunk.start));
        _player.seek(start);
        position = start;
      } else {
        _player.pause();
        _player.seek(end);
        position = end;
      }
    }
    if (mounted) setState(() => _position = position);
  }

  Future<void> _playSelection() async {
    final chunk = _selectedChunk;
    final path = _audioPath;
    if (chunk == null || path == null) return;
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play(
        DeviceFileSource(path),
        position: Duration(milliseconds: _milliseconds(chunk.start)),
      );
    }
  }

  void _changeTime(String id, String field, double value) {
    final chunk = _chunks.firstWhere((item) => item.id == id);
    setState(() {
      if (field == 'start') {
        chunk.start = value.clamp(0, chunk.end).toDouble();
      } else {
        chunk.end = value < chunk.start ? chunk.start : value;
      }
      _hasChanges = true;
    });
  }

  void _changeTranscript(String id, String text) {
    final chunk = _chunks.firstWhere((item) => item.id == id);
    if (chunk.text == text) return;
    setState(() {
      chunk.text = text;
      _hasChanges = true;
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
        _showSplitDialog();
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
    setState(() {
      _chunks.remove(chunk);
      _selectedId = null;
      _hasChanges = true;
    });
  }

  void _showSplitDialog() {
    final chunk = _selectedChunk;
    if (chunk == null) return;
    final controller = TextEditingController(text: chunk.text);
    showDialog<void>(
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

  void _autoDetectAudio() {
    final message = _chunks.isEmpty
        ? 'No local SRT segments are available for this exam.'
        : 'Using ${_chunks.length} local SRT segments as the detected audio transcript.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _translateToVietnamese() async {
    if (AppConfig.geminiApiKey.isEmpty) {
      _showMessage(
        'Set GEMINI_API_KEY at build time to translate transcripts.',
      );
      return;
    }
    if (_chunks.isEmpty) return;
    setState(() => _isTranslating = true);
    try {
      final entries = _chunks
          .map((chunk) => {'id': chunk.id, 'text': chunk.text})
          .toList();
      final response = await http.post(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/${AppConfig.geminiModel}:generateContent?key=${AppConfig.geminiApiKey}',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'text':
                      'Translate each English transcript to Vietnamese. Return only a JSON object mapping each id to its translation. Input: ${jsonEncode(entries)}',
                },
              ],
            },
          ],
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Translation request failed (${response.statusCode}).',
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final raw =
          data['candidates'][0]['content']['parts'][0]['text'] as String;
      final cleaned = raw
          .replaceAll(RegExp(r'^```json\s*|\s*```$', multiLine: true), '')
          .trim();
      final translations = jsonDecode(cleaned) as Map<String, dynamic>;
      setState(() {
        for (final chunk in _chunks) {
          final translation = translations[chunk.id];
          if (translation is String) chunk.hint = translation;
        }
        _hasChanges = true;
      });
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
  String _format(Duration value) =>
      (value.inMilliseconds / 1000).toStringAsFixed(2);

  @override
  void dispose() {
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
            chunks: _chunks,
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
        onPressed: _autoDetectAudio,
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Auto-detect Audio'),
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

  Widget _progressBar() {
    final maximum = _duration.inMilliseconds == 0
        ? 1.0
        : _duration.inMilliseconds.toDouble();
    final current = _position.inMilliseconds
        .clamp(0, maximum.toInt())
        .toDouble();
    return Row(
      children: [
        IconButton.filled(
          onPressed: _selectedChunk == null ? null : _playSelection,
          icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
        ),
        const SizedBox(width: 8),
        Text(_format(_position)),
        Expanded(
          child: Slider(
            value: current,
            max: maximum,
            onChanged: (value) {
              final position = Duration(milliseconds: value.round());
              _player.seek(position);
              setState(() => _position = position);
            },
          ),
        ),
        Text(_format(_duration)),
      ],
    );
  }
}
