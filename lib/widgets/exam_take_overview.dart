import 'package:flutter/material.dart';

import '../models.dart';
import '../services/exam_summary_service.dart';
import '../services/local_database.dart';
import 'attempt_analytics_dialog.dart';

class ExamTakeOverview extends StatefulWidget {
  const ExamTakeOverview({
    super.key,
    required this.exam,
    required this.onStartPractice,
    required this.onStartReal,
    required this.onStartDictation,
    required this.onRetakeQuestions,
    required this.onReviewQuestions,
  });
  final Exam exam;
  final void Function(List<int> parts, List<String> tags) onStartPractice;
  final VoidCallback onStartReal;
  final VoidCallback onStartDictation;
  final ValueChanged<List<String>> onRetakeQuestions;
  final ValueChanged<List<String>> onReviewQuestions;
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
      ExamSummaryService.instance.loadQuestionTags(widget.exam.id),
      ExamSummaryService.instance.loadAttempts(widget.exam.id),
      LocalDatabase.instance.loadSrtChunks(widget.exam.id),
    ]);
    if (!mounted) return;
    setState(() {
      _contexts = results[0] as List<ExamContext>;
      _tags = results[1] as List<String>;
      _attempts = results[2] as List<AttemptSummary>;
      _chunks = results[3] as List<SrtChunk>;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final parts = _contexts.map((item) => item.part).toSet().toList()..sort();
    final count = _contexts.fold(
      0,
      (total, item) => total + item.questions.length,
    );
    return ListView(
      children: [
        Text(
          widget.exam.title,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
        Text(
          '${widget.exam.duration} min | ${parts.length} parts | $count questions',
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
                  children: [_practice(parts), _realTest(count), _dictation()],
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
                  DataColumn(label: Text('Mode')),
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
                          DataCell(
                            Text(
                              attempt.mode == 'real' ? 'Real Test' : 'Practice',
                            ),
                          ),
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
                              tooltip: 'View attempt analytics',
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
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Parts', style: TextStyle(fontWeight: FontWeight.bold)),
        Wrap(
          spacing: 5,
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
            spacing: 5,
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

  Widget _realTest(int count) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Full exam: $count questions, ${widget.exam.duration} minutes.'),
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
    final ready =
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
          if (!ready)
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
            onPressed: _chunks.isNotEmpty && ready
                ? widget.onStartDictation
                : null,
            icon: const Icon(Icons.headphones),
            label: const Text('Start Dictation'),
          ),
        ],
      ),
    );
  }

  Future<void> _viewAttempt(AttemptSummary attempt) => showDialog<void>(
    context: context,
    builder: (_) => AttemptAnalyticsDialog(
      attempt: attempt,
      onRetake: widget.onRetakeQuestions,
      onReview: widget.onReviewQuestions,
    ),
  );
  String _duration(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}
