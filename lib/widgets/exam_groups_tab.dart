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
    child: ExpansionTile(
      title: Text(
        'Context ${context.index + 1} · ${context.type.replaceAll('_', ' ')}',
      ),
      subtitle: Text(
        context.questions.isEmpty
            ? 'No questions'
            : 'Questions ${context.questions.map((item) => item.number).join(', ')}',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
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
                _playingContext == context.id ? Icons.pause : Icons.play_arrow,
              ),
              label: Text(
                '${context.audioStart.toStringAsFixed(2)} – ${context.audioEnd.toStringAsFixed(2)}',
              ),
            ),
          ),
        for (final question in context.questions) _question(question),
      ],
    ),
  );

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
