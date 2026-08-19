import 'dart:convert';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/attempt_detail_service.dart';
import '../services/local_database.dart';

class ExamTakeOverview extends StatefulWidget {
  const ExamTakeOverview({
    super.key,
    required this.exam,
    required this.onStartPractice,
    required this.onStartReal,
    required this.onStartDictation,
  });

  final Exam exam;
  final void Function(List<int> parts, List<String> tags) onStartPractice;
  final VoidCallback onStartReal;
  final VoidCallback onStartDictation;

  @override
  State<ExamTakeOverview> createState() => _ExamTakeOverviewState();
}

class _ExamTakeOverviewState extends State<ExamTakeOverview> {
  List<ExamContext> _contexts = [];
  List<String> _tags = [];
  List<AttemptSummary> _attempts = [];
  List<SrtChunk> _chunks = [];
  final _selectedParts = <int>{};
  final _selectedTags = <String>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      LocalDatabase.instance.loadExamContexts(widget.exam.id),
      LocalDatabase.instance.loadExamQuestionTags(widget.exam.id),
      LocalDatabase.instance.loadAttemptSummaries(widget.exam.id),
      LocalDatabase.instance.loadSrtChunks(widget.exam.id),
    ]);
    if (mounted) {
      setState(() {
        _contexts = results[0] as List<ExamContext>;
        _tags = results[1] as List<String>;
        _attempts = results[2] as List<AttemptSummary>;
        _chunks = results[3] as List<SrtChunk>;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final parts = _contexts.map((item) => item.part).toSet().toList()..sort();
    final questionCount = _contexts.fold(
      0,
      (count, context) => count + context.questions.length,
    );
    return ListView(
      children: [
        Text(
          widget.exam.title,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
        Text(
          '${widget.exam.duration} min | ${parts.length} parts | $questionCount questions',
          style: const TextStyle(color: Color(0xff5f6368)),
        ),
        if (widget.exam.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(widget.exam.description),
          ),
        const SizedBox(height: 14),
        _history(),
        const SizedBox(height: 14),
        DefaultTabController(
          length: 3,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Practice'),
                  Tab(text: 'Real Test'),
                  Tab(text: 'Dictation'),
                ],
              ),
              SizedBox(
                height: 230,
                child: TabBarView(
                  children: [
                    _practice(parts),
                    _realTest(questionCount),
                    _dictation(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _history() => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Previous Attempts',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_attempts.isEmpty)
            const Text(
              'No attempts yet.',
              style: TextStyle(color: Color(0xff5f6368)),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('Duration')),
                  DataColumn(label: Text('Score')),
                  DataColumn(label: Text('Accuracy')),
                  DataColumn(label: Text('Parts')),
                  DataColumn(label: Text('Question Tags')),
                  DataColumn(label: Text('View')),
                ],
                rows: _attempts
                    .map(
                      (attempt) => DataRow(
                        cells: [
                          DataCell(Text(attempt.createdAt)),
                          DataCell(Text(_duration(attempt.durationSeconds))),
                          DataCell(
                            Text(
                              '${attempt.totalCorrect}/${attempt.totalQuestions}',
                            ),
                          ),
                          DataCell(
                            Text('${attempt.accuracy.toStringAsFixed(1)}%'),
                          ),
                          DataCell(
                            Text(
                              attempt.selectedParts.isEmpty
                                  ? 'All'
                                  : attempt.selectedParts
                                        .map((part) => 'Part $part')
                                        .join(', '),
                            ),
                          ),
                          DataCell(
                            Text(
                              attempt.questionTags.isEmpty
                                  ? 'Untagged'
                                  : attempt.questionTags.join(', '),
                            ),
                          ),
                          DataCell(
                            IconButton(
                              icon: const Icon(Icons.visibility),
                              tooltip: 'View attempt summary',
                              onPressed: () => _viewAttempt(attempt),
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _practice(List<int> parts) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Parts', style: TextStyle(fontWeight: FontWeight.bold)),
        Wrap(
          children: [
            for (final part in parts)
              FilterChip(
                label: Text('Part $part'),
                selected: _selectedParts.contains(part),
                onSelected: (selected) => setState(
                  () => selected
                      ? _selectedParts.add(part)
                      : _selectedParts.remove(part),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Question Tags',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        if (_tags.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'No tags yet',
              style: TextStyle(color: Color(0xff5f6368)),
            ),
          )
        else
          Wrap(
            children: [
              for (final tag in _tags)
                FilterChip(
                  label: Text(tag),
                  selected: _selectedTags.contains(tag),
                  onSelected: (selected) => setState(
                    () => selected
                        ? _selectedTags.add(tag)
                        : _selectedTags.remove(tag),
                  ),
                ),
            ],
          ),
        const Spacer(),
        FilledButton.icon(
          onPressed: () => widget.onStartPractice(
            _selectedParts.toList(),
            _selectedTags.toList(),
          ),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start Practice'),
        ),
      ],
    ),
  );

  Widget _realTest(int questions) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Full exam: $questions questions, ${widget.exam.duration} minutes.',
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: widget.onStartReal,
          icon: const Icon(Icons.timer_outlined),
          label: const Text('Start Real Test'),
        ),
      ],
    ),
  );

  Widget _dictation() {
    final audioReady =
        (widget.exam.audioName ?? widget.exam.audioPath ?? '').isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_chunks.length} transcript chunk(s) available for listening practice.',
          ),
          if (_chunks.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Attach or import a transcript before starting dictation.',
                style: TextStyle(
                  color: Color(0xffd93025),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (!audioReady)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'This exam has no audio file, so playback is unavailable.',
                style: TextStyle(
                  color: Color(0xffd93025),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _chunks.isNotEmpty && audioReady
                ? widget.onStartDictation
                : null,
            icon: const Icon(Icons.headphones),
            label: const Text('Start Dictation'),
          ),
        ],
      ),
    );
  }

  Future<void> _viewAttempt(AttemptSummary attempt) async {
    final rows = await AttemptDetailService.instance.loadAnswers(attempt.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Attempt Analytics'),
        content: SizedBox(
          width: 760,
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Results: ${attempt.totalCorrect}/${attempt.totalQuestions}  •  Accuracy: ${attempt.accuracy.toStringAsFixed(1)}%  •  Time: ${_duration(attempt.durationSeconds)}',
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(
                  children: [for (final row in rows) _answerDetail(row)],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _answerDetail(Map<String, Object?> row) {
    final correct = (row['is_correct'] as num?)?.toInt() == 1;
    final options = _options(row['options']);
    final answer = row['user_choice'] as String?;
    final key = row['correct_answer'] as String? ?? '';
    final context = _contentText(row['context_content']);
    final contextNote = _note(row['context_meta']);
    final questionNote = _note(row['question_meta']);
    String optionText(String letter) {
      final index = letter.isEmpty ? -1 : letter.codeUnitAt(0) - 65;
      return index >= 0 && index < options.length ? options[index] : '';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Q${row['question_number']}: ${correct
                  ? 'Correct'
                  : answer == null
                  ? 'Skipped'
                  : 'Wrong'}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: correct
                    ? Colors.green
                    : answer == null
                    ? Colors.grey
                    : Colors.red,
              ),
            ),
            if (context.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(context),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text('${row['content']}'),
            ),
            Text(
              'Your answer: ${answer ?? 'not answered'} ${optionText(answer ?? '')}\nCorrect answer: $key ${optionText(key)}',
            ),
            if (contextNote.isNotEmpty)
              Text(
                'Context note: $contextNote',
                style: const TextStyle(color: Color(0xff52616b)),
              ),
            if (questionNote.isNotEmpty)
              Text(
                'Question note: $questionNote',
                style: const TextStyle(color: Color(0xff174ea6)),
              ),
          ],
        ),
      ),
    );
  }

  List<dynamic> _options(Object? value) {
    try {
      return value is String && jsonDecode(value) is List
          ? jsonDecode(value) as List
          : [];
    } catch (_) {
      return [];
    }
  }

  String _contentText(Object? value) {
    try {
      final map = value is String ? jsonDecode(value) : value;
      return map is Map ? '${map['text'] ?? ''}' : '';
    } catch (_) {
      return '';
    }
  }

  String _note(Object? value) {
    try {
      final map = value is String ? jsonDecode(value) : value;
      return map is Map ? '${map['note'] ?? ''}' : '';
    } catch (_) {
      return '';
    }
  }

  String _duration(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}
