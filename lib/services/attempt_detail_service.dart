import 'dart:convert';

import '../models.dart';
import 'local_database.dart';

class AttemptDetailService {
  AttemptDetailService._();

  static final instance = AttemptDetailService._();

  Future<List<AttemptAnswerDetail>> loadAnswers(String attemptId) async {
    final rows = await (await LocalDatabase.instance.database).rawQuery(
      '''
      SELECT a.question_id, a.user_choice, a.is_correct, q.question_number, q.content,
             q.options, q.correct_answer, q.question_type, c.part,
             c.id AS context_id, c.content AS context_content,
             c.additional_meta AS context_meta, q.additional_meta AS question_meta,
             GROUP_CONCAT(t.tag_name, char(31)) AS context_tags
      FROM user_answers a
      JOIN exam_questions q ON q.id = a.question_id
      JOIN exam_contexts c ON c.id = q.context_id
      LEFT JOIN user_question_tags t ON t.context_id = c.id
      WHERE a.attempt_id = ? GROUP BY a.id ORDER BY q.question_number
    ''',
      [attemptId],
    );
    return rows.map(_detailFromRow).toList();
  }

  AttemptAnswerDetail _detailFromRow(Map<String, Object?> row) =>
      AttemptAnswerDetail(
        questionId: row['question_id'] as String,
        contextId: row['context_id'] as String,
        questionNumber: (row['question_number'] as num?)?.toInt() ?? 0,
        part: (row['part'] as num?)?.toInt() ?? 1,
        category: (row['question_type'] as String?)?.trim().isNotEmpty == true
            ? row['question_type'] as String
            : 'Question',
        content: row['content'] as String? ?? '',
        contextText: _text(row['context_content']),
        contextNote: _note(row['context_meta']),
        questionNote: _note(row['question_meta']),
        tags: (row['context_tags'] as String? ?? '')
            .split(String.fromCharCode(31))
            .where((tag) => tag.isNotEmpty)
            .toList(),
        options: _options(row['options']),
        userChoice: row['user_choice'] as String?,
        correctAnswer: row['correct_answer'] as String? ?? '',
        isCorrect: (row['is_correct'] as num?)?.toInt() == 1,
      );

  List<String> _options(Object? value) {
    try {
      final decoded = value is String ? jsonDecode(value) : value;
      return decoded is List ? decoded.map((option) => '$option').toList() : [];
    } on FormatException {
      return [];
    }
  }

  String _text(Object? value) {
    try {
      final decoded = value is String ? jsonDecode(value) : value;
      return decoded is Map ? '${decoded['text'] ?? ''}' : '';
    } on FormatException {
      return '';
    }
  }

  String _note(Object? value) {
    try {
      final decoded = value is String ? jsonDecode(value) : value;
      return decoded is Map ? '${decoded['note'] ?? ''}' : '';
    } on FormatException {
      return '';
    }
  }
}
