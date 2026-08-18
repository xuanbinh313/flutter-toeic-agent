import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config.dart';
import '../models.dart';

class LocalDatabase {
  LocalDatabase._();
  static final instance = LocalDatabase._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final databasePath = await _findDatabasePath();
    _database = await openDatabase(databasePath, version: 1);
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
            audioName: row['audio_name'] as String?,
            audioPath: row['full_audio_url'] as String?,
          ),
        )
        .toList();
  }

  Future<List<Vocab>> loadVocabulary() async {
    final rows = await (await database).query(
      'vocabulary',
      orderBy: 'ord ASC, word COLLATE NOCASE',
    );
    return rows
        .map(
          (row) => Vocab(
            row['word'] as String,
            (row['meaning'] as String?) ?? '',
            (row['source_text'] as String?) ?? '',
            (row['status'] as num?)?.toInt() ?? 1,
            row['id'] as String,
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

  Future<void> updateExam(Exam exam) => database.then(
    (db) => db.update(
      'exams',
      {
        'title': exam.title,
        'description': exam.description,
        'duration_minutes': exam.duration,
        'is_published': exam.published ? 1 : 0,
        'audio_name': exam.audioName,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [exam.id],
    ),
  );

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
      );
    }).toList();
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
    if (value is List<dynamic>) return value;
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List<dynamic>) return decoded;
      } on FormatException {
        // Invalid legacy JSON is treated as an empty value.
      }
    }
    return [];
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
}
