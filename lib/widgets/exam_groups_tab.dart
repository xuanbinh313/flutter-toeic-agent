import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/local_database.dart';
import '../services/range_audio_player.dart';
import 'context_tag_dialog.dart';
import 'vocabulary_selectable_text.dart';

class ExamGroupsTab extends StatefulWidget {
  const ExamGroupsTab({
    super.key,
    required this.exam,
    this.questionIds = const [],
    this.onClearQuestionFilter,
    this.onVocabularyAdded,
  });

  final Exam exam;
  final List<String> questionIds;
  final VoidCallback? onClearQuestionFilter;
  final VoidCallback? onVocabularyAdded;

  @override
  State<ExamGroupsTab> createState() => _ExamGroupsTabState();
}

class _ExamGroupsTabState extends State<ExamGroupsTab> {
  late final _rangePlayer = RangeAudioPlayer(
    onChanged: () {
      if (mounted) setState(() {});
    },
  );
  List<ExamContext> _contexts = [];
  Map<String, Set<String>> _contextTags = {};
  int? _part;
  bool _loading = true;
  StreamSubscription<void>? _windowsSubscription;

  bool _matchesReview(ExamContext context) =>
      widget.questionIds.isEmpty ||
      context.questions.any(
        (question) => widget.questionIds.contains(question.id),
      );

  Iterable<ExamQuestion> _visibleQuestions(ExamContext context) =>
      context.questions.where(
        (question) =>
            widget.questionIds.isEmpty ||
            widget.questionIds.contains(question.id),
      );

  @override
  void initState() {
    super.initState();
    _load();
    _windowsSubscription = onWindowsChanged.listen((_) => _load());
  }

  Future<void> _load() async {
    final values = await Future.wait([
      LocalDatabase.instance.loadExamContexts(widget.exam.id),
      LocalDatabase.instance.loadContextTags(widget.exam.id),
    ]);
    final contexts = values[0] as List<ExamContext>;
    final parts = contexts
        .where(_matchesReview)
        .map((context) => context.part)
        .toSet();
    if (mounted) {
      setState(() {
        _contexts = contexts;
        _contextTags = values[1] as Map<String, Set<String>>;
        // Tag changes refresh the data but must not send the learner back to
        // the first part tab.
        _part = parts.contains(_part)
            ? _part
            : (contexts.isEmpty ? null : contexts.first.part);
        _loading = false;
      });
    }
  }

  Future<void> _openAgentImport() async {
    final arguments = jsonEncode({
      'window': 'import-questions-agent',
      'examId': widget.exam.id,
    });
    final existing = await WindowController.getAll();
    for (final controller in existing) {
      if (controller.arguments == arguments) {
        await controller.show();
        return;
      }
    }
    final controller = await WindowController.create(
      WindowConfiguration(arguments: arguments, hiddenAtLaunch: false),
    );
    await controller.show();
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
    await _rangePlayer.toggle(
      id: context.id,
      path: path,
      startSeconds: context.audioStart,
      endSeconds: context.audioEnd,
    );
  }

  Future<void> _refresh() async {
    widget.onClearQuestionFilter?.call();
    await _load();
  }

  @override
  void dispose() {
    _windowsSubscription?.cancel();
    _rangePlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final reviewContexts = _contexts.where(_matchesReview).toList();
    final parts = reviewContexts.map((item) => item.part).toSet().toList()
      ..sort();
    final activePart = parts.contains(_part)
        ? _part
        : (parts.isEmpty ? null : parts.first);
    final contexts = reviewContexts
        .where((item) => item.part == activePart)
        .toList();
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
              onPressed: _openAgentImport,
              tooltip: 'Import questions with agent',
              icon: const Icon(Icons.smart_toy_outlined),
            ),
            IconButton(
              onPressed: () => _editContext(),
              tooltip: 'Add context',
              icon: const Icon(Icons.add),
            ),
            IconButton(
              onPressed: _refresh,
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (parts.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final part in parts)
                ChoiceChip(
                  label: Text('Part $part'),
                  selected: part == activePart,
                  onSelected: (_) => setState(() => _part = part),
                ),
            ],
          ),
        ],
        if (widget.questionIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Review filter: ${widget.questionIds.length} wrong or skipped question(s)',
              style: const TextStyle(color: Color(0xff1a73e8)),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: contexts.isEmpty
              ? const Center(
                  child: Text(
                    'No groups or questions are available for this exam.',
                  ),
                )
              : ListView(
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
                onPressed: () => _manageTags(context),
                icon: const Icon(Icons.sell_outlined),
                label: Text(
                  _contextTags[context.id]?.isEmpty ?? true ? 'Tag' : 'Tagged',
                ),
                style: TextButton.styleFrom(
                  foregroundColor: _contextTags[context.id]?.isEmpty ?? true
                      ? null
                      : const Color(0xff1a73e8),
                ),
              ),
            ],
          ),
          Text(
            _visibleQuestions(context).isEmpty
                ? 'No questions'
                : 'Questions ${_visibleQuestions(context).map((item) => item.number).join(', ')}',
            style: const TextStyle(color: Color(0xff52616b)),
          ),
          const SizedBox(height: 10),
          if (context.imagePath != null &&
              File(context.imagePath!).existsSync())
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Image.file(File(context.imagePath!), fit: BoxFit.contain),
            ),
          if (context.text.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: VocabularySelectableText(
                  text: context.text,
                  contextId: context.id,
                  sourceText: context.text,
                  onVocabularyAdded: widget.onVocabularyAdded,
                ),
              ),
            ),
          if (context.note.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: VocabularySelectableText(
                  text: context.note,
                  contextId: context.id,
                  sourceText: context.text,
                  style: const TextStyle(color: Color(0xff52616b)),
                  onVocabularyAdded: widget.onVocabularyAdded,
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
                  _rangePlayer.playingId == context.id
                      ? Icons.pause
                      : Icons.play_arrow,
                ),
                label: Text(
                  '${context.audioStart.toStringAsFixed(2)} – ${context.audioEnd.toStringAsFixed(2)}',
                ),
              ),
            ),
          for (final question in _visibleQuestions(context))
            _question(question, context),
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

  Future<void> _manageTags(ExamContext context) async {
    await showDialog<void>(
      context: this.context,
      builder: (_) =>
          ContextTagDialog(examId: widget.exam.id, contextId: context.id),
    );
    if (mounted) await _load();
  }

  Widget _question(ExamQuestion question, ExamContext context) => Padding(
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
            VocabularySelectableText(
              text: question.content,
              contextId: context.id,
              sourceText: context.text,
              onVocabularyAdded: widget.onVocabularyAdded,
            ),
            for (var i = 0; i < question.options.length; i++)
              VocabularySelectableText(
                text: '${String.fromCharCode(65 + i)}. ${question.options[i]}',
                contextId: context.id,
                sourceText: context.text,
                style: TextStyle(
                  fontWeight:
                      question.correctAnswer.toUpperCase() ==
                          String.fromCharCode(65 + i)
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
                onVocabularyAdded: widget.onVocabularyAdded,
              ),
            if (question.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: VocabularySelectableText(
                  text: question.note,
                  contextId: context.id,
                  sourceText: context.text,
                  style: const TextStyle(color: Color(0xff52616b)),
                  onVocabularyAdded: widget.onVocabularyAdded,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
