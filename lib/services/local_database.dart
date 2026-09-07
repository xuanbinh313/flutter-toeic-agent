import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config.dart';
import '../models.dart';
import 'local_schema_service.dart';
import 'uuid.dart';

class LocalDatabase {
  LocalDatabase._();
  static final instance = LocalDatabase._();
  Database? _database;

  Future<void> initialize() async => database.then((_) {});

  Future<Database> get database async {
    if (_database != null) return _database!;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final databasePath = await _findDatabasePath();
    _database = await openDatabase(databasePath, version: 1);
    await LocalSchemaService.ensure(_database!);
    return _database!;
  }

  Future<String> _findDatabasePath() async {
    if (AppConfig.databasePath.isNotEmpty) return AppConfig.databasePath;
    final projectDatabase = path.join(Directory.current.path, 'exams.db');
    if (File(projectDatabase).existsSync()) return projectDatabase;
    final appDirectory = await getApplicationSupportDirectory();
    return path.join(appDirectory.path, 'exams.db');
  }

  Future<List<Exam>> loadExams() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT e.id, e.title, e.description, e.duration_minutes, e.is_published, e.audio_name, e.full_audio_url,
             e.created_at,
             COUNT(q.id) AS question_count
      FROM exams e
      LEFT JOIN exam_contexts c ON c.exam_id = e.id
      LEFT JOIN exam_questions q ON q.context_id = c.id
      GROUP BY e.id
      ORDER BY e.updated_at DESC, e.created_at DESC
    ''');
    return rows
        .map(
          (row) => Exam(
            id: row['id'] as String,
            title: row['title'] as String,
            description: (row['description'] as String?) ?? '',
            duration: (row['duration_minutes'] as num?)?.toInt() ?? 0,
            questions: (row['question_count'] as num?)?.toInt() ?? 0,
            published: (row['is_published'] as num?)?.toInt() == 1,
            createdAt: (row['created_at'] as String?) ?? '',
            audioName: row['audio_name'] as String?,
            audioPath: row['full_audio_url'] as String?,
          ),
        )
        .toList();
  }

  Future<List<SrtChunk>> loadSrtChunks(String examId) async {
    final rows = await (await database).query(
      'exam_srt_chunks',
      where: 'exam_id = ?',
      whereArgs: [examId],
      orderBy: '"index" ASC, start_time ASC',
    );
    if (rows.isNotEmpty) {
      return rows
          .map(
            (row) => SrtChunk(
              id: row['id'] as String,
              index: (row['index'] as num).toInt(),
              start: (row['start_time'] as num).toDouble(),
              end: (row['end_time'] as num).toDouble(),
              text: row['text'] as String,
              hint: row['hint'] as String?,
            ),
          )
          .toList();
    }
    final legacy = await (await database).query(
      'exams',
      columns: ['srt_chunks'],
      where: 'id = ?',
      whereArgs: [examId],
      limit: 1,
    );
    final raw = legacy.isEmpty ? null : legacy.first['srt_chunks'] as String?;
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(
            (value) => SrtChunk(
              id:
                  value['id'] as String? ??
                  'legacy-${value['index']}-${value['start_time']}',
              index: (value['index'] as num?)?.toInt() ?? 0,
              start: (value['start_time'] as num?)?.toDouble() ?? 0,
              end: (value['end_time'] as num?)?.toDouble() ?? 0,
              text: value['text'] as String? ?? '',
              hint: value['hint'] as String?,
            ),
          )
          .toList();
    } on FormatException {
      return [];
    }
  }

  Future<void> saveSrtChunks(String examId, List<SrtChunk> chunks) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(
        'exam_srt_chunks',
        where: 'exam_id = ?',
        whereArgs: [examId],
      );
      for (var index = 0; index < chunks.length; index++) {
        final chunk = chunks[index];
        chunk.index = index;
        await transaction.insert('exam_srt_chunks', <String, Object?>{
          'id': chunk.id,
          'exam_id': examId,
          'index': index,
          'start_time': chunk.start,
          'end_time': chunk.end,
          'text': chunk.text,
          'hint': chunk.hint,
          'additional_meta': '{}',
          'dirty': 1,
        });
      }
    });
  }

  Future<void> updateExam(Exam exam) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    if (exam.id.isEmpty) {
      exam.id = newUuid();
      await db.insert('exams', {
        'id': exam.id,
        'title': exam.title,
        'description': exam.description,
        'duration_minutes': exam.duration,
        'is_published': exam.published ? 1 : 0,
        'audio_name': exam.audioName,
        'full_audio_url': exam.audioPath,
        'created_at': now,
        'updated_at': now,
        'dirty': 1,
        'srt_chunks': '',
      });
      return;
    }
    await db.update(
      'exams',
      {
        'title': exam.title,
        'description': exam.description,
        'duration_minutes': exam.duration,
        'is_published': exam.published ? 1 : 0,
        'audio_name': exam.audioName,
        'updated_at': now,
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [exam.id],
    );
  }

  Future<List<ExamContext>> loadExamContexts(String examId) async {
    final db = await database;
    final contexts = await db.query(
      'exam_contexts',
      where: 'exam_id = ?',
      whereArgs: [examId],
      orderBy: 'part ASC, "index" ASC',
    );
    final questions = await db.rawQuery(
      '''
      SELECT q.* FROM exam_questions q
      JOIN exam_contexts c ON c.id = q.context_id
      WHERE c.exam_id = ? ORDER BY q.question_number ASC
    ''',
      [examId],
    );
    final byContext = <String, List<ExamQuestion>>{};
    for (final row in questions) {
      final contextId = row['context_id'] as String;
      byContext.putIfAbsent(contextId, () => []).add(_questionFromRow(row));
    }
    return contexts.map((row) {
      final content = _jsonMap(row['content']);
      final meta = _jsonMap(row['additional_meta']);
      return ExamContext(
        id: row['id'] as String,
        part: (row['part'] as num?)?.toInt() ?? 1,
        type: row['context_type'] as String? ?? '',
        index: (row['index'] as num?)?.toInt() ?? 0,
        text: content['text'] as String? ?? '',
        note: meta['note'] as String? ?? '',
        audioStart: (meta['audio_start'] as num?)?.toDouble() ?? 0,
        audioEnd: (meta['audio_end'] as num?)?.toDouble() ?? 0,
        questions: byContext[row['id'] as String] ?? [],
        imagePath: content['image_path'] as String?,
        imageFilename: content['image_filename'] as String?,
      );
    }).toList();
  }

  Future<Map<String, Set<String>>> loadContextTags(String examId) async {
    final rows = await (await database).rawQuery(
      '''
      SELECT t.context_id, t.tag_name FROM user_question_tags t
      JOIN exam_contexts c ON c.id = t.context_id WHERE c.exam_id = ?
    ''',
      [examId],
    );
    final tags = <String, Set<String>>{};
    for (final row in rows) {
      tags
          .putIfAbsent(row['context_id'] as String, () => {})
          .add(row['tag_name'] as String);
    }
    return tags;
  }

  Future<void> saveAttempt({
    required String examId,
    required int totalCorrect,
    required int totalQuestions,
    required int durationSeconds,
    required List<({String questionId, String? choice, bool correct})> answers,
    required List<int> selectedParts,
    required List<String> selectedTags,
    required String mode,
    required List<int> activeParts,
    required List<String> activeQuestionTags,
    required List<String> questionIds,
  }) async {
    final attemptId = newUuid();
    final now = DateTime.now().toUtc().toIso8601String();
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.insert('exam_attempts', {
        'id': attemptId,
        'exam_id': examId,
        'total_correct': totalCorrect,
        'total_questions': totalQuestions,
        'final_score': totalQuestions == 0
            ? null
            : totalCorrect * 100 / totalQuestions,
        'duration_seconds': durationSeconds,
        'created_at': now,
        'dirty': 1,
        'additional_meta': jsonEncode({
          'mode': mode,
          // An empty selection means "all parts". Persist the resolved parts so
          // attempt history always states precisely what was practised.
          'selected_parts': selectedParts.isEmpty ? activeParts : selectedParts,
          'selected_tags': selectedTags,
          'question_tags': activeQuestionTags,
          'question_ids': questionIds,
        }),
      });
      for (final answer in answers) {
        await transaction.insert('user_answers', {
          'id': newUuid(),
          'attempt_id': attemptId,
          'question_id': answer.questionId,
          'user_choice': answer.choice,
          'is_correct': answer.correct ? 1 : 0,
          'dirty': 1,
        });
      }
    });
  }

  ExamQuestion _questionFromRow(Map<String, Object?> row) {
    final meta = _jsonMap(row['additional_meta']);
    final options = _jsonList(row['options']).map((value) => '$value').toList();
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

  Map<String, dynamic> _jsonMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) return decoded;
      } on FormatException {
        // Invalid legacy JSON is treated as an empty value.
      }
    }
    return {};
  }

  List<dynamic> _jsonList(Object? value) {
    var decoded = value;
    // Older Jun Edu exports may JSON-encode the options column twice.
    for (var attempt = 0; attempt < 3; attempt++) {
      if (decoded is List<dynamic>) return decoded;
      if (decoded is! String) return [];
      try {
        decoded = jsonDecode(decoded);
      } on FormatException {
        return [];
      }
    }
    return [];
  }

  Future<void> deleteContext(String contextId) => database.then(
    (db) => db.transaction((tx) async {
      await tx.delete(
        'exam_questions',
        where: 'context_id = ?',
        whereArgs: [contextId],
      );
      await tx.delete(
        'user_question_tags',
        where: 'context_id = ?',
        whereArgs: [contextId],
      );
      await tx.delete('exam_contexts', where: 'id = ?', whereArgs: [contextId]);
    }),
  );

  Future<void> saveContext({
    required String examId,
    String? id,
    required int part,
    required String type,
    required String text,
    required String note,
    required double audioStart,
    required double audioEnd,
    List<ExamQuestion> questions = const [],
    String? imagePath,
  }) async {
    final contextId = id ?? newUuid();
    final db = await database;
    await db.transaction((tx) async {
      final context = {
        'id': contextId,
        'exam_id': examId,
        'part': part,
        'context_type': type,
        'content': jsonEncode({
          'text': text,
          if (imagePath != null && imagePath.isNotEmpty) ...{
            'image_path': imagePath,
            'image_filename': path.basename(imagePath),
          },
        }),
        'index': 0,
        'additional_meta': jsonEncode({
          'note': note,
          'audio_start': audioStart,
          'audio_end': audioEnd,
        }),
        'dirty': 1,
      };
      if (id == null) {
        await tx.insert('exam_contexts', context);
      } else {
        await tx.update(
          'exam_contexts',
          context,
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      if (questions.isNotEmpty) {
        await tx.delete(
          'exam_questions',
          where: 'context_id = ?',
          whereArgs: [contextId],
        );
        for (final question in questions) {
          await tx.insert('exam_questions', {
            'id': question.id.isEmpty ? newUuid() : question.id,
            'context_id': contextId,
            'question_number': question.number,
            'question_type': question.type,
            'content': question.content,
            'options': jsonEncode(question.options),
            'correct_answer': question.correctAnswer,
            'additional_meta': jsonEncode({'note': question.note}),
            'dirty': 1,
          });
        }
      }
    });
  }

  Future<void> updateContextAudioSegment(
    String contextId, {
    required double start,
    required double end,
  }) async {
    final db = await database;
    final rows = await db.query(
      'exam_contexts',
      columns: ['additional_meta'],
      where: 'id = ?',
      whereArgs: [contextId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final meta = _jsonMap(rows.first['additional_meta']);
    meta['audio_start'] = start;
    meta['audio_end'] = end;
    await db.update(
      'exam_contexts',
      {'additional_meta': jsonEncode(meta), 'dirty': 1},
      where: 'id = ?',
      whereArgs: [contextId],
    );
  }

  Future<void> setContextTag(String contextId, String tag, bool enabled) async {
    final db = await database;
    if (enabled) {
      final exists = await db.query(
        'user_question_tags',
        where: 'context_id = ? AND tag_name = ?',
        whereArgs: [contextId, tag],
        limit: 1,
      );
      if (exists.isEmpty) {
        await db.insert('user_question_tags', {
          'id': newUuid(),
          'context_id': contextId,
          'tag_name': tag,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'dirty': 1,
        });
      }
    } else {
      await db.delete(
        'user_question_tags',
        where: 'context_id = ? AND tag_name = ?',
        whereArgs: [contextId, tag],
      );
    }
  }

  Future<void> updateVocabularyStatus(Vocab word) => (database.then(
    (db) => db.update(
      'vocabulary',
      {
        'status': word.status,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [word.id],
    ),
  ));

  Future<Vocab> addVocabulary({
    required String word,
    required String contextId,
    required String sourceText,
  }) async {
    final normalizedWord = word.trim();
    if (normalizedWord.isEmpty) {
      throw ArgumentError.value(
        word,
        'word',
        'Vocabulary word cannot be empty.',
      );
    }
    final db = await database;
    final orderRows = await db.rawQuery(
      'SELECT COALESCE(MAX(ord), -1) + 1 AS next_order FROM vocabulary',
    );
    final order = (orderRows.first['next_order'] as num?)?.toInt() ?? 0;
    final now = DateTime.now().toUtc().toIso8601String();
    final vocabulary = Vocab(normalizedWord, '', sourceText, 1, newUuid());
    await db.insert('vocabulary', {
      'id': vocabulary.id,
      'context_id': contextId,
      'word': vocabulary.word,
      'meaning': vocabulary.meaning,
      'source_text': vocabulary.source,
      'status': vocabulary.status,
      'ord': order,
      'data': '{}',
      'created_at': now,
      'updated_at': now,
      'dirty': 1,
    });
    return vocabulary;
  }
}
