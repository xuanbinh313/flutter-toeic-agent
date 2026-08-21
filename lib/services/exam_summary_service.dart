import 'dart:convert';

import '../models.dart';
import 'local_database.dart';

class ExamSummaryService {
  ExamSummaryService._();

  static final instance = ExamSummaryService._();

  Future<List<String>> loadQuestionTags(String examId) async {
    final rows = await (await LocalDatabase.instance.database).rawQuery(
      '''
      SELECT DISTINCT t.tag_name FROM user_question_tags t
      JOIN exam_contexts c ON c.id = t.context_id
      WHERE c.exam_id = ? ORDER BY t.tag_name COLLATE NOCASE
    ''',
      [examId],
    );
    return rows.map((row) => row['tag_name'] as String).toList();
  }

  Future<List<AttemptSummary>> loadAttempts(String examId) async {
    final rows = await (await LocalDatabase.instance.database).query(
      'exam_attempts',
      where: 'exam_id = ?',
      whereArgs: [examId],
      orderBy: 'created_at DESC',
    );
    return Future.wait(
      rows.map((row) async {
        final meta = _map(row['additional_meta']);
        var selectedParts = _list(
          meta['selected_parts'],
        ).map((item) => int.tryParse('$item')).whereType<int>().toList();
        var questionTags = _list(
          meta['question_tags'],
        ).map((item) => '$item').toList();
        if (selectedParts.isEmpty || questionTags.isEmpty) {
          final derived = await _derivedFilters(row['id'] as String);
          if (selectedParts.isEmpty) selectedParts = derived.$1;
          if (questionTags.isEmpty) questionTags = derived.$2;
        }
        return AttemptSummary(
          id: row['id'] as String,
          createdAt: row['created_at'] as String? ?? '',
          durationSeconds: (row['duration_seconds'] as num?)?.toInt() ?? 0,
          totalCorrect: (row['total_correct'] as num?)?.toInt() ?? 0,
          totalQuestions: (row['total_questions'] as num?)?.toInt() ?? 0,
          selectedParts: selectedParts,
          questionTags: questionTags,
          mode: meta['mode'] as String? ?? 'practice',
        );
      }),
    );
  }

  Future<(List<int>, List<String>)> _derivedFilters(String attemptId) async {
    final rows = await (await LocalDatabase.instance.database).rawQuery(
      '''SELECT DISTINCT c.part, t.tag_name
         FROM user_answers a JOIN exam_questions q ON q.id = a.question_id
         JOIN exam_contexts c ON c.id = q.context_id
         LEFT JOIN user_question_tags t ON t.context_id = c.id
         WHERE a.attempt_id = ?''',
      [attemptId],
    );
    final parts =
        rows
            .map((row) => (row['part'] as num?)?.toInt())
            .whereType<int>()
            .toSet()
            .toList()
          ..sort();
    final tags =
        rows
            .map((row) => row['tag_name'] as String?)
            .whereType<String>()
            .toSet()
            .toList()
          ..sort();
    return (parts, tags);
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is! String) return {};
    try {
      return (jsonDecode(value) as Map?)?.cast<String, dynamic>() ?? {};
    } on FormatException {
      return {};
    }
  }

  List<dynamic> _list(Object? value) {
    if (value is List<dynamic>) return value;
    if (value is! String) return [];
    try {
      return jsonDecode(value) as List<dynamic>;
    } on FormatException {
      return [];
    }
  }
}
