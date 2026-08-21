import 'package:flutter/material.dart';

import '../models.dart';
import '../services/attempt_detail_service.dart';

class AttemptAnalyticsDialog extends StatefulWidget {
  const AttemptAnalyticsDialog({
    super.key,
    required this.attempt,
    required this.onRetake,
  });

  final AttemptSummary attempt;
  final ValueChanged<List<String>> onRetake;

  @override
  State<AttemptAnalyticsDialog> createState() => _AttemptAnalyticsDialogState();
}

class _AttemptAnalyticsDialogState extends State<AttemptAnalyticsDialog> {
  late final Future<List<AttemptAnswerDetail>> _answers = AttemptDetailService
      .instance
      .loadAnswers(widget.attempt.id);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Attempt Analytics'),
    content: SizedBox(
      width: 900,
      height: 620,
      child: FutureBuilder<List<AttemptAnswerDetail>>(
        future: _answers,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Text('Could not load attempt: ${snapshot.error}');
          }
          final answers = snapshot.data ?? [];
          return _content(answers);
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );

  Widget _content(List<AttemptAnswerDetail> answers) {
    final correct = answers.where((answer) => answer.isCorrect).length;
    final skipped = answers.where((answer) => answer.isSkipped).length;
    final wrong = answers.length - correct - skipped;
    final parts = answers.map((answer) => answer.part).toSet().toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _metric('Results', '$correct / ${answers.length}', Colors.blue),
            _metric(
              'Accuracy',
              '${widget.attempt.accuracy.toStringAsFixed(1)}%',
              Colors.blue,
            ),
            _metric(
              'Time',
              _duration(widget.attempt.durationSeconds),
              Colors.blue,
            ),
            _metric('Correct', '$correct', Colors.green),
            _metric('Wrong', '$wrong', Colors.red),
            _metric('Skipped', '$skipped', Colors.grey),
          ],
        ),
        const SizedBox(height: 12),
        DefaultTabController(
          length: parts.length + 1,
          child: Expanded(
            child: Column(
              children: [
                TabBar(
                  isScrollable: true,
                  tabs: [
                    const Tab(text: 'Overall'),
                    for (final part in parts) Tab(text: 'Part $part'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _breakdown(answers),
                      for (final part in parts)
                        _breakdown(
                          answers
                              .where((answer) => answer.part == part)
                              .toList(),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Answer Sheet',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final answer in answers) _answerTile(answer)],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => _retake(answers),
            icon: const Icon(Icons.redo),
            label: const Text('Retake Wrong Answers'),
          ),
        ),
      ],
    );
  }

  Widget _metric(String label, String value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      children: [
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
        Text(label),
      ],
    ),
  );

  Widget _breakdown(List<AttemptAnswerDetail> answers) {
    final categories = <String, List<AttemptAnswerDetail>>{};
    for (final answer in answers) {
      categories.putIfAbsent(answer.category, () => []).add(answer);
    }
    return ListView(
      padding: const EdgeInsets.only(top: 8),
      children: [
        for (final entry in categories.entries)
          _categoryRow(AttemptCategoryBreakdown(entry.key, entry.value)),
      ],
    );
  }

  Widget _categoryRow(AttemptCategoryBreakdown category) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            category.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Correct ${category.correct}   Wrong ${category.wrong}   Skipped ${category.skipped}   Accuracy ${category.accuracy.toStringAsFixed(1)}%',
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [for (final answer in category.answers) _badge(answer)],
          ),
        ],
      ),
    ),
  );

  Widget _badge(AttemptAnswerDetail answer) => Tooltip(
    message:
        'Q${answer.questionNumber} | ${answer.tags.isEmpty ? 'Untagged' : answer.tags.join(', ')}',
    child: InkWell(
      onTap: () => _details(answer),
      child: CircleAvatar(
        radius: 15,
        backgroundColor: _statusColor(answer).withValues(alpha: .18),
        child: Text(
          '${answer.questionNumber}',
          style: TextStyle(color: _statusColor(answer)),
        ),
      ),
    ),
  );

  Widget _answerTile(AttemptAnswerDetail answer) => OutlinedButton(
    onPressed: () => _details(answer),
    style: OutlinedButton.styleFrom(foregroundColor: _statusColor(answer)),
    child: Text(
      'Q${answer.questionNumber}  Key ${answer.correctAnswer}: ${answer.userChoice ?? '—'}',
    ),
  );

  Color _statusColor(AttemptAnswerDetail answer) => answer.isCorrect
      ? Colors.green
      : answer.isSkipped
      ? Colors.grey
      : Colors.red;

  Future<void> _details(AttemptAnswerDetail answer) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Question ${answer.questionNumber}'),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (answer.contextText.isNotEmpty)
                _section('Context', answer.contextText),
              if (answer.contextNote.isNotEmpty)
                _section('Context note', answer.contextNote),
              _section('Question', answer.content),
              if (answer.questionNote.isNotEmpty)
                _section('Question note', answer.questionNote),
              _section(
                'Answers',
                'Your answer: ${answer.userChoice ?? 'not answered'} ${answer.optionText(answer.userChoice)}\nCorrect answer: ${answer.correctAnswer} ${answer.optionText(answer.correctAnswer)}',
              ),
            ],
          ),
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

  Widget _section(String label, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 3),
        SelectableText(text),
      ],
    ),
  );

  void _retake(List<AttemptAnswerDetail> answers) {
    final ids = answers
        .where((answer) => !answer.isCorrect)
        .map((answer) => answer.questionId)
        .toList();
    if (ids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('There are no wrong or skipped answers to retake.'),
        ),
      );
      return;
    }
    Navigator.pop(context);
    widget.onRetake(ids);
  }

  String _duration(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}
