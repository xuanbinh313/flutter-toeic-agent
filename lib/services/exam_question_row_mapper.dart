import '../models.dart';
import 'local_database_json.dart';

class ExamQuestionRowMapper {
  const ExamQuestionRowMapper._();

  static ExamQuestion fromRow(Map<String, Object?> row) {
    final meta = decodeLocalJsonMap(row['additional_meta']);
    final options = decodeLocalJsonList(
      row['options'],
    ).map((value) => '$value').toList();
    return ExamQuestion(
      id: row['id'] as String,
      number: (row['question_number'] as num?)?.toInt() ?? 0,
      type: row['question_type'] as String? ?? '',
      content: row['content'] as String? ?? '',
      options: options,
      correctAnswer: row['correct_answer'] as String? ?? '',
      note: meta['note'] as String? ?? '',
    );
  }
}
