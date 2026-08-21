import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/local_database.dart';
import '../services/range_audio_player.dart';
import '../widgets/context_tag_dialog.dart';
import '../widgets/reminder_button.dart';
import 'session_question.dart';

class ExamSessionPage extends StatefulWidget {
  const ExamSessionPage({
    super.key,
    required this.exam,
    required this.realTest,
    this.parts = const [],
    this.tags = const [],
    this.questionIds = const [],
  });

  final Exam exam;
  final bool realTest;
  final List<int> parts;
  final List<String> tags;
  final List<String> questionIds;

  @override
  State<ExamSessionPage> createState() => _ExamSessionPageState();
}

class _ExamSessionPageState extends State<ExamSessionPage> {
  late final _rangePlayer = RangeAudioPlayer(
    onChanged: () {
      if (mounted) setState(() {});
    },
  );
  final _answers = <String, String?>{};
  List<SessionQuestion> _questions = [];
  Map<String, Set<String>> _contextTags = {};
  DateTime? _startedAt;
  Timer? _timer;
  int? _activePart;
  bool _loading = true;
  bool _submitting = false;
  bool _showResult = false;
  int _correct = 0;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final contexts = await LocalDatabase.instance.loadExamContexts(
      widget.exam.id,
    );
    _contextTags = await LocalDatabase.instance.loadContextTags(widget.exam.id);
    final selectedParts = widget.parts.toSet();
    final selectedTags = widget.tags.toSet();
    _questions = [
      for (final context in contexts)
        if ((widget.realTest ||
                selectedParts.isEmpty ||
                selectedParts.contains(context.part)) &&
            (widget.realTest ||
                selectedTags.isEmpty ||
                selectedTags
                    .intersection(_contextTags[context.id] ?? {})
                    .isNotEmpty))
          for (final question in context.questions)
            if (widget.questionIds.isEmpty ||
                widget.questionIds.contains(question.id))
              SessionQuestion(context, question),
    ];
    _startedAt = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  void _tick() {
    if (_startedAt == null || _showResult) return;
    final elapsed = DateTime.now().difference(_startedAt!).inSeconds;
    if (widget.realTest &&
        elapsed >= widget.exam.duration * 60 &&
        widget.exam.duration > 0) {
      _submit();
      return;
    }
    if (mounted) setState(() => _elapsed = elapsed);
  }

  String? get _audioPath {
    final source = widget.exam.audioName ?? widget.exam.audioPath;
    if (source == null || source.isEmpty) return null;
    if (File(source).existsSync()) return source;
    final appData = Platform.environment['APPDATA'];
    final path = appData == null
        ? ''
        : '$appData${Platform.pathSeparator}jun-toeic${Platform.pathSeparator}${source.split(RegExp(r'[\\/]')).last}';
    return File(path).existsSync() ? path : null;
  }

  Future<void> _playContext(ExamContext context) async {
    final path = _audioPath;
    if (path == null || context.audioEnd <= context.audioStart) return;
    await _rangePlayer.toggle(
      id: context.id,
      path: path,
      startSeconds: context.audioStart,
      endSeconds: context.audioEnd,
    );
  }

  Future<void> _submit() async {
    if (_submitting || _showResult) return;
    _timer?.cancel();
    final correct = _questions
        .where(
          (item) =>
              _answers[item.question.id] ==
              item.question.correctAnswer.toUpperCase(),
        )
        .length;
    setState(() {
      _submitting = true;
      _correct = correct;
    });
    await LocalDatabase.instance.saveAttempt(
      examId: widget.exam.id,
      totalCorrect: correct,
      totalQuestions: _questions.length,
      durationSeconds: _elapsed,
      selectedParts: widget.parts,
      selectedTags: widget.tags,
      mode: widget.realTest ? 'real' : 'practice',
      activeParts: _questions.map((item) => item.context.part).toSet().toList()
        ..sort(),
      activeQuestionTags:
          _questions
              .expand(
                (item) => _contextTags[item.context.id] ?? const <String>{},
              )
              .toSet()
              .toList()
            ..sort(),
      questionIds: _questions.map((item) => item.question.id).toList(),
      answers: [
        for (final item in _questions)
          (
            questionId: item.question.id,
            choice: _answers[item.question.id],
            correct:
                _answers[item.question.id] ==
                item.question.correctAnswer.toUpperCase(),
          ),
      ],
    );
    if (mounted) {
      setState(() {
        _submitting = false;
        _showResult = true;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rangePlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_showResult) return _result();
    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Exam')),
        body: const Center(
          child: Text('No questions match the selected mode or filters.'),
        ),
      );
    }
    final parts = _questions.map((item) => item.context.part).toSet().toList()
      ..sort();
    final questions = _questions
        .where(
          (item) => _activePart == null || item.context.part == _activePart,
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.realTest ? 'Real Test' : 'Practice'),
        actions: [
          const ReminderButton(compact: true),
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Center(
              child: Text(
                widget.realTest && widget.exam.duration > 0
                    ? 'Remaining ${_format((widget.exam.duration * 60 - _elapsed).clamp(0, widget.exam.duration * 60))}'
                    : 'Elapsed ${_format(_elapsed)}',
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All Parts'),
                    selected: _activePart == null,
                    onSelected: (_) => setState(() => _activePart = null),
                  ),
                  for (final part in parts)
                    ChoiceChip(
                      label: Text('Part $part'),
                      selected: _activePart == part,
                      onSelected: (_) => setState(() => _activePart = part),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(child: ListView(children: _contextSections(questions))),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: const Icon(Icons.check),
                label: Text(_submitting ? 'Submitting...' : 'Submit'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _contextSections(List<SessionQuestion> questions) {
    final grouped = <String, List<SessionQuestion>>{};
    for (final item in questions) {
      grouped.putIfAbsent(item.context.id, () => []).add(item);
    }
    return [
      for (final group in grouped.values)
        _contextCard(group.first.context, group),
    ];
  }

  Widget _contextCard(
    ExamContext context,
    List<SessionQuestion> questions,
  ) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Part ${context.part} | Context ${context.index + 1} | Questions ${questions.first.question.number}${questions.length == 1 ? '' : '-${questions.last.question.number}'}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: () => _manageTags(context),
                tooltip: (_contextTags[context.id]?.isEmpty ?? true)
                    ? 'Manage tags for this context'
                    : 'Tagged: ${_contextTags[context.id]!.join(', ')}',
                color: _contextTags[context.id]?.isEmpty ?? true
                    ? null
                    : const Color(0xff1a73e8),
                icon: const Icon(Icons.sell_outlined),
              ),
              if (context.audioEnd > context.audioStart)
                OutlinedButton.icon(
                  onPressed: _audioPath == null
                      ? null
                      : () => _playContext(context),
                  icon: Icon(
                    _rangePlayer.playingId == context.id
                        ? Icons.pause
                        : Icons.play_arrow,
                  ),
                  label: const Text('Listen'),
                ),
            ],
          ),
          if (context.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: SelectableText(context.text),
            ),
          if (_contextImage(context) != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Center(child: _contextImage(context)!),
            ),
          for (final item in questions) _questionCard(item),
        ],
      ),
    ),
  );

  Future<void> _manageTags(ExamContext context) async {
    await showDialog<void>(
      context: this.context,
      builder: (_) =>
          ContextTagDialog(examId: widget.exam.id, contextId: context.id),
    );
    final tags = await LocalDatabase.instance.loadContextTags(widget.exam.id);
    if (mounted) setState(() => _contextTags = tags);
  }

  Widget? _contextImage(ExamContext context) {
    final filename = context.imageFilename;
    final appData = Platform.environment['APPDATA'];
    final local = filename == null || appData == null
        ? null
        : File(
            '$appData${Platform.pathSeparator}jun-toeic${Platform.pathSeparator}$filename',
          );
    final direct = context.imagePath == null ? null : File(context.imagePath!);
    final file = local?.existsSync() == true
        ? local
        : direct?.existsSync() == true
        ? direct
        : null;
    if (file == null) return null;
    return Image.file(
      file,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) =>
          const Text('Could not load context image.'),
    );
  }

  Widget _questionCard(SessionQuestion item) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Question ${item.question.number}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        SelectableText(item.question.content),
        RadioGroup<String>(
          groupValue: _answers[item.question.id],
          onChanged: (value) =>
              setState(() => _answers[item.question.id] = value),
          child: Column(
            children: [
              for (var i = 0; i < item.question.options.length; i++)
                RadioListTile<String>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: String.fromCharCode(65 + i),
                  title: Text(
                    '${String.fromCharCode(65 + i)}. ${item.question.options[i]}',
                  ),
                ),
            ],
          ),
        ),
        if (!widget.realTest)
          TextButton.icon(
            onPressed: () => setState(() => _answers[item.question.id] = null),
            icon: const Icon(Icons.skip_next),
            label: const Text('Skip'),
          ),
      ],
    ),
  );

  Widget _result() => Scaffold(
    appBar: AppBar(title: const Text('Results')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Score: $_correct / ${_questions.length} (${(_questions.isEmpty ? 0 : _correct * 100 / _questions.length).toStringAsFixed(1)}%)',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            children: [
              _counter('Correct', _correct, Colors.green),
              _counter(
                'Wrong',
                _questions
                    .where(
                      (item) =>
                          _answers[item.question.id] != null &&
                          _answers[item.question.id] !=
                              item.question.correctAnswer.toUpperCase(),
                    )
                    .length,
                Colors.red,
              ),
              _counter(
                'Skipped',
                _questions
                    .where((item) => _answers[item.question.id] == null)
                    .length,
                Colors.grey,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [for (final item in _questions) _resultCard(item)],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back to Exam'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _counter(String label, int value, Color color) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label),
      ],
    ),
  );
  Widget _resultCard(SessionQuestion item) {
    final answer = _answers[item.question.id];
    final correct = answer == item.question.correctAnswer.toUpperCase();
    return Card(
      child: ListTile(
        title: Text(
          'Question ${item.question.number}: ${correct ? 'Correct' : 'Wrong'}',
          style: TextStyle(
            color: correct ? Colors.green : Colors.red,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '${item.question.content}\nYour answer: ${answer ?? 'Unanswered'}\nCorrect answer: ${item.question.correctAnswer}',
        ),
        isThreeLine: true,
      ),
    );
  }

  String _format(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}
