import 'package:flutter/material.dart';

import '../models.dart';
import 'exam_workspace.dart';

class ExamLibrary extends StatefulWidget {
  const ExamLibrary({super.key, required this.exams, required this.changed});
  final List<Exam> exams;
  final VoidCallback changed;

  @override
  State<ExamLibrary> createState() => _ExamLibraryState();
}

class _ExamLibraryState extends State<ExamLibrary> {
  String _query = '';

  Future<void> _addExam() async {
    final created = await showDialog<Exam>(
      context: context,
      builder: (_) => const _ExamDialog(),
    );
    if (created != null) {
      setState(() => widget.exams.add(created));
      widget.changed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.exams
        .where(
          (exam) => exam.title.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Exam Library',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Color(0xff102a43),
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Manage your study sets and learner practice sessions.',
                      style: TextStyle(color: Color(0xff52616b)),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _addExam,
                icon: const Icon(Icons.add),
                label: const Text('Add exam'),
              ),
            ],
          ),
          const SizedBox(height: 22),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search exams...',
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: visible.isEmpty
                ? const Center(child: Text('No exams found.'))
                : ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, index) => _ExamCard(
                      exam: visible[index],
                      changed: widget.changed,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.exam, required this.changed});
  final Exam exam;
  final VoidCallback changed;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: ListTile(
      contentPadding: const EdgeInsets.all(16),
      leading: const CircleAvatar(
        backgroundColor: Color(0xffe8f0fe),
        child: Icon(Icons.description_outlined, color: Color(0xff1a73e8)),
      ),
      title: Text(
        exam.title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(exam.description),
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              children: [
                Chip(label: Text('${exam.duration} min')),
                Chip(label: Text('${exam.questions} questions')),
                Chip(label: Text(exam.published ? 'Published' : 'Draft')),
              ],
            ),
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ExamWorkspace(exam: exam, changed: changed),
        ),
      ),
    ),
  );
}

class _ExamDialog extends StatefulWidget {
  const _ExamDialog();
  @override
  State<_ExamDialog> createState() => _ExamDialogState();
}

class _ExamDialogState extends State<_ExamDialog> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _duration = TextEditingController(text: '45');
  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _duration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create exam'),
    content: SizedBox(
      width: 410,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Exam title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _duration,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Duration (minutes)'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_title.text.trim().isNotEmpty) {
            Navigator.pop(
              context,
              Exam(
                title: _title.text.trim(),
                description: _description.text.trim().isEmpty
                    ? 'New exam ready for questions and contexts.'
                    : _description.text.trim(),
                duration: int.tryParse(_duration.text) ?? 45,
                questions: 0,
              ),
            );
          }
        },
        child: const Text('Create'),
      ),
    ],
  );
}
