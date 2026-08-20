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
    return rows.map((row) {
      final meta = _map(row['additional_meta']);
      return AttemptSummary(
        id: row['id'] as String,
        createdAt: row['created_at'] as String? ?? '',
        durationSeconds: (row['duration_seconds'] as num?)?.toInt() ?? 0,
        totalCorrect: (row['total_correct'] as num?)?.toInt() ?? 0,
        totalQuestions: (row['total_questions'] as num?)?.toInt() ?? 0,
        selectedParts: _list(
          meta['selected_parts'],
        ).map((item) => int.tryParse('$item')).whereType<int>().toList(),
        questionTags: _list(
          meta['question_tags'],
        ).map((item) => '$item').toList(),
      );
    }).toList();
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
