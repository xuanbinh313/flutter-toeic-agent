import 'local_database.dart';

class AttemptDetailService {
  AttemptDetailService._();

  static final instance = AttemptDetailService._();

  Future<List<Map<String, Object?>>> loadAnswers(String attemptId) =>
      LocalDatabase.instance.database.then(
        (db) => db.rawQuery(
          '''
      SELECT a.user_choice, a.is_correct, q.question_number, q.content,
             q.options, q.correct_answer, q.question_type, c.part,
             c.content AS context_content, c.additional_meta AS context_meta,
             q.additional_meta AS question_meta
      FROM user_answers a
      JOIN exam_questions q ON q.id = a.question_id
      JOIN exam_contexts c ON c.id = q.context_id
      WHERE a.attempt_id = ? ORDER BY q.question_number
    ''',
          [attemptId],
        ),
      );
}
