import 'dart:convert';

import 'package:dictation_application/features/import_questions/import_part_store.dart';
import 'package:dictation_application/services/local_schema_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, dynamic> context(int number, {String text = 'new'}) => {
  'context_type': 'IMAGE_DIAGRAM',
  'content': {'text': text, 'image_path': 'photo.png'},
  'additional_meta': {'note': 'context note'},
  'questions': [
    {
      'question_number': number,
      'content': text,
      'options': ['one', 'two'],
      'correct_answer': 'b',
      'additional_meta': {'note': 'question note'},
    },
  ],
};

void main() {
  sqfliteFfiInit();
  late Database db;
  late ImportPartStore store;

  Future<void> seed(String id, String exam, int part, int number) async {
    await db.insert('exam_contexts', {
      'id': id,
      'exam_id': exam,
      'part': part,
      'content': '{"text":"old"}',
      'index': 0,
    });
    await db.insert('exam_questions', {
      'id': '${id}_q',
      'context_id': id,
      'question_number': number,
      'content': 'old',
    });
  }

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await LocalSchemaService.ensure(db);
    store = ImportPartStore(db);
    await db.insert('exams', {'id': 'exam', 'title': 'Test'});
    await db.insert('exams', {'id': 'other', 'title': 'Other'});
    await seed('first', 'exam', 1, 1);
    await seed('duplicate', 'exam', 1, 1);
    await seed('obsolete', 'exam', 1, 2);
    await seed('part2', 'exam', 2, 11);
    await seed('other_exam', 'other', 1, 1);
    await db.insert('user_question_tags', {
      'id': 'tag',
      'context_id': 'first',
      'tag_name': 'review',
    });
  });

  tearDown(() => db.close());

  test(
    'replaces only selected exam part, retains IDs and image metadata',
    () async {
      await store.replace(
        examId: 'exam',
        part: 1,
        contexts: [context(1), context(3)],
      );
      final rows = await db.query(
        'exam_contexts',
        where: 'exam_id = ? AND part = ?',
        whereArgs: ['exam', 1],
        orderBy: '"index"',
      );
      expect(rows.length, 2);
      expect(rows.first['id'], 'first');
      expect(rows.map((r) => r['index']), [0, 1]);
      expect(
        jsonDecode(rows.first['content'] as String)['image_path'],
        'photo.png',
      );
      final questions = await db.query('exam_questions');
      expect(questions.length, 4);
      expect(
        questions.singleWhere((q) => q['id'] == 'first_q')['content'],
        'new',
      );
      expect(questions.any((q) => q['id'] == 'duplicate_q'), isFalse);
      expect(questions.any((q) => q['id'] == 'obsolete_q'), isFalse);
      expect(
        questions.singleWhere((q) => q['id'] == 'part2_q')['content'],
        'old',
      );
      expect(
        questions.singleWhere((q) => q['id'] == 'other_exam_q')['content'],
        'old',
      );
      expect(
        (await db.query('user_question_tags')).single['context_id'],
        'first',
      );
    },
  );

  test(
    'retry updates existing data without creating duplicate groups or questions',
    () async {
      await store.replace(examId: 'exam', part: 1, contexts: [context(1)]);
      await store.replace(
        examId: 'exam',
        part: 1,
        contexts: [context(1, text: 'retry')],
      );
      expect(
        (await db.query(
          'exam_contexts',
          where: 'exam_id = ? AND part = ?',
          whereArgs: ['exam', 1],
        )).length,
        1,
      );
      final rows = await db.query(
        'exam_questions',
        where: 'context_id = ?',
        whereArgs: ['first'],
      );
      expect(rows.length, 1);
      expect(rows.single['id'], 'first_q');
      expect(rows.single['content'], 'retry');
    },
  );

  test('empty or duplicate-number responses preserve existing part', () async {
    for (final response in <List<Map<String, dynamic>>>[
      [],
      [context(1), context(1)],
    ]) {
      await expectLater(
        store.replace(examId: 'exam', part: 1, contexts: response),
        throwsFormatException,
      );
      expect((await db.query('exam_contexts')).length, 5);
      expect(
        (await db.query('exam_questions')).every((q) => q['content'] == 'old'),
        isTrue,
      );
    }
  });

  test('database failure rolls back all updates and inserts', () async {
    await db.execute(
      '''CREATE TRIGGER fail_import BEFORE INSERT ON exam_questions
      WHEN NEW.question_number = 3 BEGIN SELECT RAISE(ABORT, 'test failure'); END''',
    );
    await expectLater(
      store.replace(
        examId: 'exam',
        part: 1,
        contexts: [context(1), context(3)],
      ),
      throwsA(isA<DatabaseException>()),
    );
    expect((await db.query('exam_contexts')).length, 5);
    expect((await db.query('exam_questions')).length, 5);
    expect(
      (await db.query('exam_questions')).every((q) => q['content'] == 'old'),
      isTrue,
    );
  });
}
