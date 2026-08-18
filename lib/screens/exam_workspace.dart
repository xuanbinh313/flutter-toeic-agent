import 'package:flutter/material.dart';

import '../models.dart';
import '../widgets/dictation_practice.dart';
import '../widgets/exam_details_form.dart';
import '../widgets/exam_groups_tab.dart';
import '../widgets/transcript_tab.dart';

class ExamWorkspace extends StatelessWidget {
  const ExamWorkspace({super.key, required this.exam, required this.changed});
  final Exam exam;
  final VoidCallback changed;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 7,
    child: Scaffold(
      appBar: AppBar(title: Text(exam.title)),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: const TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      Tab(
                        icon: Icon(Icons.edit_outlined),
                        text: 'Exam Details',
                      ),
                      Tab(
                        icon: Icon(Icons.segment),
                        text: 'Groups & Questions',
                      ),
                      Tab(
                        icon: Icon(Icons.play_circle_outline),
                        text: 'Practice',
                      ),
                      Tab(icon: Icon(Icons.insights_outlined), text: 'Results'),
                      Tab(icon: Icon(Icons.history), text: 'History'),
                      Tab(
                        icon: Icon(Icons.subject_outlined),
                        text: 'Transcript',
                      ),
                      Tab(
                        icon: Icon(Icons.record_voice_over_outlined),
                        text: 'Dictation',
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    exam.published = !exam.published;
                    changed();
                  },
                  icon: Icon(
                    exam.published
                        ? Icons.unpublished_outlined
                        : Icons.publish_outlined,
                  ),
                  label: Text(exam.published ? 'Unpublish' : 'Publish'),
                ),
              ],
            ),

            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                children: [
                  ExamDetailsForm(exam: exam, onSaved: changed),
                  ExamGroupsTab(exam: exam),
                  _practice(context),
                  _results(),
                  _history(),
                  TranscriptTab(
                    examId: exam.id,
                    audioSource: exam.audioName ?? exam.audioPath,
                  ),
                  _dictation(),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  // ignore: unused_element
  Widget _overview(BuildContext context) => ListView(
    children: [
      Card(
        elevation: 0,
        color: const Color(0xffedf4ff),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Wrap(
            spacing: 40,
            runSpacing: 12,
            children: [
              _metric('Duration', '${exam.duration} minutes'),
              _metric('Questions', '${exam.questions} items'),
              _metric('Status', exam.published ? 'Published' : 'Draft'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 22),
      const Text(
        'Ready to study?',
        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      const Text(
        'Practice gives immediate feedback. Real test mode checks answers when submitted.',
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 12,
        children: [_start(context, false), _start(context, true)],
      ),
      const SizedBox(height: 22),
      const Card(
        elevation: 0,
        child: ListTile(
          leading: Icon(Icons.check_circle_outline, color: Colors.green),
          title: Text('Last practice attempt'),
          subtitle: Text('18 / 22 correct · 12 minutes ago'),
        ),
      ),
    ],
  );
  // ignore: unused_element
  Widget _content() => ListView(
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Exam content',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add),
            label: const Text('Add question'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      ...List.generate(
        3,
        (part) => Card(
          elevation: 0,
          child: ExpansionTile(
            leading: CircleAvatar(child: Text('${part + 1}')),
            title: Text('Part ${part + 1}'),
            subtitle: Text('Contexts and questions'),
            children: List.generate(
              2,
              (item) => ListTile(
                leading: const Icon(Icons.article_outlined),
                title: Text('Context ${item + 1}'),
                subtitle: Text(
                  'Questions ${(part * 3) + item + 1}–${(part * 3) + item + 3}',
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
  Widget _practice(BuildContext context) => Center(
    child: Wrap(
      spacing: 12,
      children: [_start(context, false), _start(context, true)],
    ),
  );
  Widget _results() => ListView(
    children: [
      const Text(
        'Latest result',
        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 10),
      const Card(
        elevation: 0,
        child: ListTile(
          leading: SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(value: .82),
          ),
          title: Text('82% · 18 of 22 correct'),
          subtitle: Text('Practice mode · today'),
        ),
      ),
      const SizedBox(height: 12),
      ...['Part 1 · 7 / 8', 'Part 2 · 6 / 8', 'Part 3 · 5 / 6'].map(
        (item) => Card(
          elevation: 0,
          child: ListTile(
            leading: const Icon(Icons.bar_chart),
            title: Text(item),
          ),
        ),
      ),
    ],
  );
  Widget _history() => ListView(
    children: [
      const Text(
        'Attempt history',
        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 10),
      ...[
        ('Today, 10:32', 'Practice', '82%'),
        ('Yesterday, 16:18', 'Real test', '73%'),
        ('12 Aug, 09:45', 'Practice', '68%'),
      ].map(
        (item) => Card(
          elevation: 0,
          child: ListTile(
            leading: const Icon(Icons.history),
            title: Text(item.$2),
            subtitle: Text(item.$1),
            trailing: Text(item.$3),
          ),
        ),
      ),
    ],
  );
  Widget _dictation() => DictationPractice(
    examId: exam.id,
    audioName: exam.audioName ?? exam.audioPath,
  );
  Widget _start(BuildContext context, bool timed) => timed
      ? OutlinedButton.icon(
          onPressed: () => _quiz(context, true),
          icon: const Icon(Icons.timer_outlined),
          label: const Text('Real test mode'),
        )
      : FilledButton.icon(
          onPressed: () => _quiz(context, false),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start practice'),
        );
  Widget _metric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xff52616b),
        ),
      ),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    ],
  );
  void _quiz(BuildContext context, bool timed) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => QuizPage(exam: exam, timed: timed),
    ),
  );
}

class QuizPage extends StatefulWidget {
  const QuizPage({super.key, required this.exam, required this.timed});
  final Exam exam;
  final bool timed;
  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  int _index = 0;
  final _answers = <int, int>{};
  final _questions = const [
    (
      'The committee _____ the budget.',
      ['allocated', 'allocation', 'allocating', 'allocate'],
      0,
    ),
    (
      'Please submit a _____ report.',
      ['comprehend', 'comprehensive', 'comprehensively', 'comprehension'],
      1,
    ),
    (
      'Sales are expected to _____.',
      ['decline', 'declined', 'declining', 'declines'],
      0,
    ),
  ];
  @override
  Widget build(BuildContext context) {
    final question = _questions[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.exam.title),
        actions: [
          if (widget.timed)
            const Padding(
              padding: EdgeInsets.only(right: 18),
              child: Center(child: Text('Remaining 44:32')),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Question ${_index + 1} of ${_questions.length}',
              style: const TextStyle(
                color: Color(0xff1a73e8),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            Text(question.$1, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 20),
            RadioGroup<int>(
              groupValue: _answers[_index],
              onChanged: (value) => setState(() => _answers[_index] = value!),
              child: Column(
                children: List.generate(
                  question.$2.length,
                  (i) => RadioListTile<int>(
                    value: i,
                    title: Text(
                      '${String.fromCharCode(65 + i)}. ${question.$2[i]}',
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _index == 0
                      ? null
                      : () => setState(() => _index--),
                  child: const Text('Previous'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    if (_index == _questions.length - 1) {
                      final score = _answers.entries
                          .where(
                            (entry) => _questions[entry.key].$3 == entry.value,
                          )
                          .length;
                      showDialog<void>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Practice complete'),
                          content: Text(
                            'You answered $score of ${_questions.length} correctly.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                Navigator.pop(context);
                              },
                              child: const Text('Back to exam'),
                            ),
                          ],
                        ),
                      );
                    } else {
                      setState(() => _index++);
                    }
                  },
                  child: Text(
                    _index == _questions.length - 1
                        ? 'Submit test'
                        : 'Next question',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
