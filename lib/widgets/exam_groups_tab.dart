import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/local_database.dart';

class ExamGroupsTab extends StatefulWidget {
  const ExamGroupsTab({super.key, required this.exam});

  final Exam exam;

  @override
  State<ExamGroupsTab> createState() => _ExamGroupsTabState();
}

class _ExamGroupsTabState extends State<ExamGroupsTab> {
  final _player = AudioPlayer();
  List<ExamContext> _contexts = [];
  int? _part;
  bool _loading = true;
  String? _playingContext;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final contexts = await LocalDatabase.instance.loadExamContexts(
      widget.exam.id,
    );
    if (mounted) {
      setState(() {
        _contexts = contexts;
        _part = contexts.isEmpty ? null : contexts.first.part;
        _loading = false;
      });
    }
  }

  String? get _audioPath {
    final source = widget.exam.audioName ?? widget.exam.audioPath;
    if (source == null || source.isEmpty) return null;
    if (File(source).existsSync()) return source;
    final appData = Platform.environment['APPDATA'];
    final filename = source.split(RegExp(r'[\\/]')).last;
    final path = appData == null
        ? ''
        : '$appData${Platform.pathSeparator}jun-toeic${Platform.pathSeparator}$filename';
    return File(path).existsSync() ? path : null;
  }

  Future<void> _playContext(ExamContext context) async {
    final path = _audioPath;
    if (path == null || context.audioEnd <= context.audioStart) return;
    if (_playingContext == context.id) {
      await _player.pause();
      if (mounted) setState(() => _playingContext = null);
      return;
    }
    await _player.play(
      DeviceFileSource(path),
      position: Duration(milliseconds: (context.audioStart * 1000).round()),
    );
    if (mounted) setState(() => _playingContext = context.id);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_contexts.isEmpty) {
      return const Center(
        child: Text('No groups or questions are available for this exam.'),
      );
    }
    final parts = _contexts.map((item) => item.part).toSet().toList()..sort();
    final contexts = _contexts.where((item) => item.part == _part).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Groups & Questions',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            IconButton(
              onPressed: () => _editContext(),
              tooltip: 'Add context',
              icon: const Icon(Icons.add),
            ),
            IconButton(
              onPressed: _load,
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final part in parts)
              ChoiceChip(
                label: Text('Part $part'),
                selected: part == _part,
                onSelected: (_) => setState(() => _part = part),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            children: [for (final item in contexts) _contextCard(item)],
          ),
        ),
      ],
    );
  }

  Widget _contextCard(ExamContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Context ${context.index + 1} · ${context.type.replaceAll('_', ' ')}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 3),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => _editContext(context),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
              TextButton.icon(
                onPressed: () => _deleteContext(context),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
              TextButton.icon(
                onPressed: () => _addTag(context),
                icon: const Icon(Icons.sell_outlined),
                label: const Text('Tag'),
              ),
            ],
          ),
          Text(
            context.questions.isEmpty
                ? 'No questions'
                : 'Questions ${context.questions.map((item) => item.number).join(', ')}',
            style: const TextStyle(color: Color(0xff52616b)),
          ),
          const SizedBox(height: 10),
          if (context.text.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(context.text),
              ),
            ),
          if (context.note.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  context.note,
                  style: const TextStyle(color: Color(0xff52616b)),
                ),
              ),
            ),
          if (context.audioEnd > context.audioStart)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _audioPath == null
                    ? null
                    : () => _playContext(context),
                icon: Icon(
                  _playingContext == context.id
                      ? Icons.pause
                      : Icons.play_arrow,
                ),
                label: Text(
                  '${context.audioStart.toStringAsFixed(2)} – ${context.audioEnd.toStringAsFixed(2)}',
                ),
              ),
            ),
          for (final question in context.questions) _question(question),
        ],
      ),
    ),
  );

  Future<void> _deleteContext(ExamContext context) async {
    final confirmed = await showDialog<bool>(
      context: this.context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete context?'),
        content: const Text('This deletes the context and its questions.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await LocalDatabase.instance.deleteContext(context.id);
    await _load();
  }

  Future<void> _editContext([ExamContext? context]) async {
    final part = TextEditingController(text: '${context?.part ?? 1}');
    final type = TextEditingController(text: context?.type ?? 'STANDALONE');
    final text = TextEditingController(text: context?.text ?? '');
    final note = TextEditingController(text: context?.note ?? '');
    final start = TextEditingController(text: '${context?.audioStart ?? 0}');
    final end = TextEditingController(text: '${context?.audioEnd ?? 0}');
    final save = await showDialog<bool>(
      context: this.context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context == null ? 'Add Context' : 'Edit Context'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: part,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Part'),
                ),
                TextField(
                  controller: type,
                  decoration: const InputDecoration(labelText: 'Context type'),
                ),
                TextField(
                  controller: text,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Passage / context text',
                  ),
                ),
                TextField(
                  controller: note,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Context note'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: start,
                        decoration: const InputDecoration(
                          labelText: 'Audio start',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: end,
                        decoration: const InputDecoration(
                          labelText: 'Audio end',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (save == true) {
      await LocalDatabase.instance.saveContext(
        examId: widget.exam.id,
        id: context?.id,
        part: int.tryParse(part.text) ?? 1,
        type: type.text.trim().isEmpty ? 'STANDALONE' : type.text.trim(),
        text: text.text.trim(),
        note: note.text.trim(),
        audioStart: double.tryParse(start.text) ?? 0,
        audioEnd: double.tryParse(end.text) ?? 0,
      );
    }
    for (final controller in [part, type, text, note, start, end]) {
      controller.dispose();
    }
    if (save == true) await _load();
  }

  Future<void> _addTag(ExamContext context) async {
    final controller = TextEditingController();
    final tag = await showDialog<String>(
      context: this.context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add context tag'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (tag == null || tag.isEmpty) return;
    await LocalDatabase.instance.setContextTag(context.id, tag, true);
    if (mounted) setState(() {});
  }

  Widget _question(ExamQuestion question) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Question ${question.number}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(question.content),
            for (var i = 0; i < question.options.length; i++)
              Text(
                '${String.fromCharCode(65 + i)}. ${question.options[i]}',
                style: TextStyle(
                  fontWeight:
                      question.correctAnswer.toUpperCase() ==
                          String.fromCharCode(65 + i)
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            if (question.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  question.note,
                  style: const TextStyle(color: Color(0xff52616b)),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
