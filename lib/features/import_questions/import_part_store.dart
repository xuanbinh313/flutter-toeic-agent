import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../services/uuid.dart';

/// Replaces a part only after its complete agent response is ready to save.
class ImportPartStore {
  ImportPartStore(this.database);

  final Database database;

  Future<void> replace({
    required String examId,
    required int part,
    required List<Map<String, dynamic>> contexts,
  }) async {
    if (part < 1 || part > 7) throw RangeError.range(part, 1, 7, 'part');
    if (contexts.isEmpty) {
      throw const FormatException('Agent response contains no contexts.');
    }
    final contextRows = <Map<String, Object?>>[];
    final questionRows = <Map<String, Object?>>[];
    final numbers = <int>{};
    final now = DateTime.now().toUtc().toIso8601String();
    for (var index = 0; index < contexts.length; index++) {
      final context = contexts[index];
      final questions = context['questions'];
      if (questions is! List) {
        throw const FormatException('Context questions must be an array.');
      }
      final firstQuestion = questions.isEmpty ? null : questions.first;
      final questionContext =
          firstQuestion is Map && firstQuestion['context'] is Map
          ? Map<String, dynamic>.from(firstQuestion['context'] as Map)
          : const <String, dynamic>{};
      final firstQuestionId = firstQuestion is Map
          ? firstQuestion['context_id'] ?? firstQuestion['contextId']
          : null;
      final responseId =
          context['context_id'] ?? context['id'] ?? firstQuestionId;
      final id = responseId is String && responseId.isNotEmpty
          ? responseId
          : newUuid();
      final content =
          context['content'] ??
          questionContext['content'] ??
          (firstQuestion is Map ? firstQuestion['context_content'] : null);
      contextRows.add({
        'id': id,
        'exam_id': examId,
        'part': part,
        'context_type':
            '${context['context_type'] ?? questionContext['context_type'] ?? (firstQuestion is Map ? firstQuestion['context_type'] : null) ?? 'STANDALONE'}'
                .toUpperCase(),
        'content': jsonEncode(content is Map ? content : {'text': '$content'}),
        'index': index,
        'additional_meta': jsonEncode(
          context['additional_meta'] ??
              questionContext['additional_meta'] ??
              (firstQuestion is Map
                  ? firstQuestion['context_additional_meta']
                  : null) ??
              {},
        ),
        'created_at': now,
        'updated_at': now,
        'dirty': 1,
      });
      for (final question in questions) {
        if (question is! Map) {
          throw const FormatException('Invalid imported question.');
        }
        final number = question['question_number'];
        if (number is! num ||
            number <= 0 ||
            number != number.toInt() ||
            !numbers.add(number.toInt())) {
          throw const FormatException(
            'Question numbers must be positive and unique within a part.',
          );
        }
        final options = question['options'];
        if (options != null && options is! List) {
          throw const FormatException('Question options must be an array.');
        }
        questionRows.add({
          'id': newUuid(),
          'context_id': id,
          'question_number': number.toInt(),
          'question_type': '${question['question_type'] ?? 'MULTIPLE_CHOICE'}'
              .toUpperCase(),
          'content': '${question['content'] ?? ''}',
          'options': jsonEncode(
            (options as List? ?? []).map((value) => '$value').toList(),
          ),
          'correct_answer': '${question['correct_answer'] ?? ''}'.toUpperCase(),
          'additional_meta': jsonEncode(question['additional_meta'] ?? {}),
          'created_at': now,
          'updated_at': now,
          'dirty': 1,
        });
      }
    }

    await database.transaction((tx) async {
      // Reuse IDs for matching questions/groups so existing review references
      // and tags survive ordinary reimports, and syncing updates those rows.
      final oldContexts = await tx.query(
        'exam_contexts',
        where: 'exam_id = ? AND part = ?',
        whereArgs: [examId, part],
      );
      final oldQuestions = await tx.rawQuery(
        '''
        SELECT q.* FROM exam_questions q JOIN exam_contexts c ON c.id = q.context_id
        WHERE c.exam_id = ? AND c.part = ?
      ''',
        [examId, part],
      );
      final otherPartNumbers = await tx.rawQuery(
        '''SELECT q.question_number FROM exam_questions q
           JOIN exam_contexts c ON c.id = q.context_id
           WHERE c.exam_id = ? AND c.part != ?''',
        [examId, part],
      );
      final importedNumbers = questionRows
          .map((question) => question['question_number'])
          .toSet();
      if (importedNumbers.length != questionRows.length ||
          otherPartNumbers.any(
            (row) => importedNumbers.contains(row['question_number']),
          )) {
        throw const FormatException(
          'Question numbers must be unique across the exam.',
        );
      }
      final usedContexts = <Object?>{};
      final usedQuestions = <Object?>{};
      for (final row in contextRows) {
        final children = questionRows
            .where((q) => q['context_id'] == row['id'])
            .toList();
        final wanted = children.map((q) => q['question_number']).toSet();
        for (final old in oldContexts) {
          final oldNumbers = oldQuestions
              .where((q) => q['context_id'] == old['id'])
              .map((q) => q['question_number'])
              .toSet();
          if (!usedContexts.contains(old['id']) &&
              oldNumbers.length == wanted.length &&
              oldNumbers.containsAll(wanted)) {
            row['id'] = old['id'];
            row['created_at'] = old['created_at'] ?? now;
            usedContexts.add(old['id']);
            break;
          }
        }
        for (final child in children) {
          child['context_id'] = row['id'];
          for (final old in oldQuestions) {
            if (old['context_id'] == row['id'] &&
                old['question_number'] == child['question_number'] &&
                !usedQuestions.contains(old['id'])) {
              child['id'] = old['id'];
              child['created_at'] = old['created_at'] ?? now;
              usedQuestions.add(old['id']);
              break;
            }
          }
        }
        if (children.isEmpty) {
          await tx.delete(
            'user_question_tags',
            where: 'context_id = ?',
            whereArgs: [row['id']],
          );
          await tx.delete(
            'exam_contexts',
            where: 'id = ? AND exam_id = ?',
            whereArgs: [row['id'], examId],
          );
        } else {
          await _save(
            tx,
            'exam_contexts',
            row,
            usedContexts.contains(row['id']),
          );
        }
      }
      // Questions are replaced by context_id, never merged by question number.
      for (final row in questionRows) {
        await _save(
          tx,
          'exam_questions',
          row,
          usedQuestions.contains(row['id']),
        );
      }
      for (final old in oldQuestions) {
        if (!usedQuestions.contains(old['id'])) {
          await tx.delete(
            'exam_questions',
            where: 'id = ?',
            whereArgs: [old['id']],
          );
        }
      }
      for (final old in oldContexts) {
        if (!usedContexts.contains(old['id'])) {
          await tx.delete(
            'user_question_tags',
            where: 'context_id = ?',
            whereArgs: [old['id']],
          );
          await tx.delete(
            'exam_contexts',
            where: 'id = ?',
            whereArgs: [old['id']],
          );
        }
      }
      final emptyContexts = await tx.rawQuery(
        '''SELECT c.id FROM exam_contexts c
           WHERE c.exam_id = ? AND NOT EXISTS (
             SELECT 1 FROM exam_questions q WHERE q.context_id = c.id
           )''',
        [examId],
      );
      for (final context in emptyContexts) {
        await tx.delete(
          'user_question_tags',
          where: 'context_id = ?',
          whereArgs: [context['id']],
        );
        await tx.delete(
          'exam_contexts',
          where: 'id = ?',
          whereArgs: [context['id']],
        );
      }
      await tx.update(
        'exams',
        {'updated_at': now, 'dirty': 1},
        where: 'id = ?',
        whereArgs: [examId],
      );
    });
  }

  Future<void> _save(
    Transaction tx,
    String table,
    Map<String, Object?> row,
    bool exists,
  ) async {
    if (exists) {
      await tx.update(table, row, where: 'id = ?', whereArgs: [row['id']]);
    } else {
      await tx.insert(table, row);
    }
  }
}
