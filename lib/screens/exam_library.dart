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
  _ExamSort _sort = _ExamSort.createdAt;

  Future<void> _addExam() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExamWorkspace(
          exam: Exam(title: '', description: '', duration: 45, questions: 0),
          changed: widget.changed,
        ),
      ),
    );
    widget.changed();
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.exams
        .where(
          (exam) => exam.title.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    visible.sort((first, second) {
      switch (_sort) {
        case _ExamSort.name:
          return first.title.toLowerCase().compareTo(
            second.title.toLowerCase(),
          );
        case _ExamSort.createdAt:
          return (second.createdAt ?? '').compareTo(first.createdAt ?? '');
      }
    });
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search exams...',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<_ExamSort>(
                value: _sort,
                onChanged: (value) => setState(() => _sort = value!),
                items: const [
                  DropdownMenuItem(value: _ExamSort.name, child: Text('Name')),
                  DropdownMenuItem(
                    value: _ExamSort.createdAt,
                    child: Text('Created date'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: visible.isEmpty
                ? const Center(child: Text('No exams found.'))
                : ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
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

enum _ExamSort { name, createdAt }

class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.exam, required this.changed});
  final Exam exam;
  final VoidCallback changed;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      leading: const CircleAvatar(
        radius: 18,
        backgroundColor: Color(0xffe8f0fe),
        child: Icon(Icons.description_outlined, color: Color(0xff1a73e8)),
      ),
      title: Text(
        exam.title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(exam.description),
            const SizedBox(height: 5),
            Wrap(
              spacing: 5,
              runSpacing: 3,
              children: [
                _ExamTag(label: '${exam.duration} min'),
                _ExamTag(label: '${exam.questions} questions'),
                _ExamTag(label: exam.published ? 'Published' : 'Draft'),
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

class _ExamTag extends StatelessWidget {
  const _ExamTag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Chip(
    label: Text(label, style: const TextStyle(fontSize: 12)),
    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
    padding: EdgeInsets.zero,
    visualDensity: VisualDensity.compact,
  );
}
