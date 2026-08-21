import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/local_database.dart';
import 'dictation_text_zoom.dart';

class DictationPractice extends StatefulWidget {
  const DictationPractice({
    super.key,
    required this.examId,
    required this.audioName,
    this.showBackButton = false,
  });

  final String examId;
  final String? audioName;
  final bool showBackButton;

  @override
  State<DictationPractice> createState() => _DictationPracticeState();
}

class _DictationPracticeState extends State<DictationPractice> {
  final _player = AudioPlayer();
  final _answerController = TextEditingController();
  final _jumpController = TextEditingController();
  final _answerFocus = FocusNode();
  List<SrtChunk> _chunks = [];
  int _currentIndex = 0;
  Duration _position = Duration.zero;
  bool _loaded = false;
  bool _playing = false;
  bool _checked = false;
  bool _answerRevealed = false;
  bool _translationRevealed = false;
  bool _showImmediately = false;
  bool _showFullAnswer = false;
  String _lastExpected = '';
  String _lastTyped = '';

  @override
  void initState() {
    super.initState();
    _load();
    _player.onPositionChanged.listen(_onPositionChanged);
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playing = state == PlayerState.playing);
    });
  }

  Future<void> _load() async {
    final chunks = await LocalDatabase.instance.loadSrtChunks(widget.examId);
    chunks.sort((a, b) => a.index.compareTo(b.index));
    if (mounted) {
      setState(() {
        _chunks = chunks;
        _loaded = true;
      });
    }
  }

  SrtChunk? get _chunk => _chunks.isEmpty ? null : _chunks[_currentIndex];

  String? get _audioPath {
    final source = widget.audioName;
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
    final chunk = _chunk;
    if (chunk != null && position.inMilliseconds >= _milliseconds(chunk.end)) {
      _player.pause();
      position = Duration(milliseconds: _milliseconds(chunk.end));
    }
    if (mounted) setState(() => _position = position);
  }

  Future<void> _play() async {
    final chunk = _chunk;
    final path = _audioPath;
    if (chunk == null || path == null) return;
    if (_playing) {
      setState(() => _playing = false);
      await _player.pause();
      return;
    }
    final start = Duration(milliseconds: _milliseconds(chunk.start));
    final end = Duration(milliseconds: _milliseconds(chunk.end));
    final resume = _position >= start && _position < end ? _position : start;
    // Desktop player-state events can arrive after the first tap. Update the
    // button immediately so the first tap reliably starts the clip.
    setState(() => _playing = true);
    try {
      await _player.play(DeviceFileSource(path), position: resume);
    } catch (_) {
      if (mounted) setState(() => _playing = false);
      rethrow;
    }
  }

  Future<void> _goTo(int index, {bool play = true}) async {
    if (index < 0 || index >= _chunks.length || index == _currentIndex) return;
    await _player.pause();
    if (!mounted) return;
    setState(() {
      _currentIndex = index;
      _resetChunkState();
    });
    if (play) await _play();
  }

  void _resetChunkState() {
    _position = Duration.zero;
    _answerController.clear();
    _jumpController.text = '${_currentIndex + 1}';
    _lastExpected = '';
    _lastTyped = '';
    _checked = false;
    _answerRevealed = false;
    _translationRevealed = false;
    _answerFocus.requestFocus();
  }

  void _checkAnswer() {
    final chunk = _chunk;
    if (chunk == null) return;
    final typed = _answerController.text;
    final expected = chunk.text;
    setState(() {
      _lastExpected = expected;
      _lastTyped = typed;
      _checked = true;
      _answerRevealed = _showImmediately;
      _translationRevealed = false;
    });
  }

  void _showAnswer() => setState(() => _answerRevealed = true);
  void _showTranslation() => setState(() => _translationRevealed = true);

  void _setShowImmediately(bool value) {
    setState(() {
      _showImmediately = value;
      if (_checked) _answerRevealed = value;
    });
  }

  bool get _isCorrect => _normalize(_lastExpected) == _normalize(_lastTyped);
  bool get _hasNote => (_chunk?.hint ?? '').trim().isNotEmpty;
  int _milliseconds(double seconds) => (seconds * 1000).round();
  String _time(double seconds) => '${seconds.toStringAsFixed(3)}s';

  @override
  void dispose() {
    _player.dispose();
    _answerController.dispose();
    _jumpController.dispose();
    _answerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_chunk == null) {
      return const Center(child: Text('No transcript chunks are available.'));
    }
    final chunk = _chunk!;
    _jumpController.text = _jumpController.text.isEmpty
        ? '${_currentIndex + 1}'
        : _jumpController.text;
    return DictationTextZoom(
      builder: (context, zoomControls) => ListView(
        children: [
          _header(zoomControls),
          const SizedBox(height: 12),
          Text(
            'Chunk ${chunk.index}: ${_time(chunk.start)} – ${_time(chunk.end)}',
            style: const TextStyle(color: Color(0xff5f6368)),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _audioPath == null ? null : _play,
            icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
            label: Text(_playing ? 'Pause' : 'Play'),
          ),
          if (_audioPath == null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'No local audio is available for this exam.',
                style: TextStyle(color: Color(0xffa15c00)),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            children: [
              _option(
                'Show answer immediately',
                _showImmediately,
                _setShowImmediately,
              ),
              _option(
                'Show full answer',
                _showFullAnswer,
                (value) => setState(() => _showFullAnswer = value),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Type what you hear',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Focus(
            focusNode: _answerFocus,
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.enter &&
                  !HardwareKeyboard.instance.isShiftPressed &&
                  !HardwareKeyboard.instance.isControlPressed &&
                  !HardwareKeyboard.instance.isAltPressed) {
                _checkAnswer();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              controller: _answerController,
              minLines: 5,
              maxLines: 5,
              enabled: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Press Enter to check. Shift+Enter adds a new line.',
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_checked) _typedAnswer(),
          if (_checked) _status(),
          if (_checked) _revealButtons(),
          if (_translationRevealed) _translation(),
          if (_answerRevealed) _answerDiff(),
        ],
      ),
    );
  }

  Widget _header(Widget zoomControls) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (widget.showBackButton)
            IconButton(
              onPressed: () => Navigator.maybePop(context),
              tooltip: 'Back to exam',
              icon: const Icon(Icons.arrow_back),
            ),
          const Expanded(
            child: Text(
              'Dictation',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          zoomControls,
          IconButton(
            tooltip: 'Previous transcript',
            onPressed: _currentIndex == 0
                ? null
                : () => _goTo(_currentIndex - 1),
            icon: const Icon(Icons.chevron_left),
          ),
          SizedBox(
            width: 58,
            child: TextField(
              controller: _jumpController,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) {
                final number = int.tryParse(value);
                if (number != null) _goTo(number - 1);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('/ ${_chunks.length}'),
          ),
          IconButton(
            tooltip: 'Next transcript',
            onPressed: _currentIndex == _chunks.length - 1
                ? null
                : () => _goTo(_currentIndex + 1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    ),
  );

  Widget _option(String label, bool value, ValueChanged<bool> changed) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Checkbox(value: value, onChanged: (next) => changed(next ?? false)),
      Text(label),
    ],
  );

  Widget _typedAnswer() => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          const TextSpan(
            text: 'Your answer: ',
            style: TextStyle(color: Color(0xff5f6368)),
          ),
          ..._typedSpans(),
        ],
      ),
    ),
  );

  Widget _status() => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      _isCorrect ? 'Correct!' : 'Incorrect',
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: _isCorrect ? const Color(0xff188038) : const Color(0xffd93025),
      ),
    ),
  );

  Widget _revealButtons() => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Wrap(
      spacing: 8,
      children: [
        if (!_answerRevealed)
          OutlinedButton.icon(
            onPressed: _showAnswer,
            icon: const Icon(Icons.visibility),
            label: const Text('Show Answer'),
          ),
        if (!_translationRevealed)
          OutlinedButton.icon(
            onPressed: _hasNote ? _showTranslation : null,
            icon: const Icon(Icons.translate),
            label: const Text('Translate'),
          ),
      ],
    ),
  );

  Widget _translation() => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xfff8fffe),
      border: Border.all(color: const Color(0xffb2dfdb)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(_chunk?.hint ?? ''),
  );

  Widget _answerDiff() => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(10),
    constraints: const BoxConstraints(minHeight: 140),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xffdadce0)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: _answerSpans(),
      ),
    ),
  );

  List<TextSpan> _typedSpans() {
    final tokens = _tokens(_lastTyped);
    final attention = _typedAttention(_lastExpected, tokens);
    return [
      for (var i = 0; i < tokens.length; i++)
        TextSpan(
          text: tokens[i],
          style: i == attention
              ? const TextStyle(
                  backgroundColor: Color(0xfffff3bf),
                  color: Color(0xff7a4f01),
                  fontWeight: FontWeight.bold,
                )
              : null,
        ),
    ];
  }

  List<TextSpan> _answerSpans() {
    final tokens = _tokens(_lastExpected);
    final attention = _answerAttention(tokens, _lastTyped);
    return [
      for (var i = 0; i < tokens.length; i++)
        TextSpan(
          text:
              !_showFullAnswer &&
                  attention != null &&
                  i > attention &&
                  tokens[i].trim().isNotEmpty
              ? _mask(tokens[i])
              : tokens[i],
          style: i == attention
              ? const TextStyle(
                  backgroundColor: Color(0xfffce8e6),
                  color: Color(0xffb3261e),
                  fontWeight: FontWeight.bold,
                )
              : null,
        ),
    ];
  }

  List<String> _tokens(String text) => RegExp(
    r'\s+|\S+',
  ).allMatches(text).map((match) => match.group(0)!).toList();
  String _word(String value) => value
      .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '')
      .toLowerCase();
  String _normalize(String value) => value
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), '')
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  String _mask(String value) => value.replaceAll(RegExp(r'\S'), '*');

  int? _typedAttention(String expected, List<String> typedTokens) {
    final words = RegExp(r'\S+')
        .allMatches(expected)
        .map((item) => _word(item.group(0)!))
        .where((item) => item.isNotEmpty)
        .toList();
    var wordIndex = 0;
    for (var i = 0; i < typedTokens.length; i++) {
      if (typedTokens[i].trim().isEmpty) continue;
      final word = _word(typedTokens[i]);
      if (word.isEmpty) continue;
      if (wordIndex >= words.length || word != words[wordIndex]) return i;
      wordIndex++;
    }
    return null;
  }

  int? _answerAttention(List<String> expectedTokens, String typed) {
    final words = RegExp(r'\S+')
        .allMatches(typed)
        .map((item) => _word(item.group(0)!))
        .where((item) => item.isNotEmpty)
        .toList();
    var wordIndex = 0;
    for (var i = 0; i < expectedTokens.length; i++) {
      if (expectedTokens[i].trim().isEmpty) continue;
      final word = _word(expectedTokens[i]);
      if (word.isEmpty) continue;
      if (wordIndex >= words.length || word != words[wordIndex]) return i;
      wordIndex++;
    }
    return null;
  }
}
