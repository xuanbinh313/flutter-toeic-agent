import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LocalSchemaService {
  LocalSchemaService._();

  static Future<void> ensure(Database db) async {
    for (final statement in _statements) {
      await db.execute(statement);
    }
    await ensureColumns(db, 'vocabulary', _vocabularyColumns);
    await _ensureVocabularyData(db);
  }

  /// The shared Supabase vocabulary table requires this JSON column. Older
  /// local databases predate it, so add and backfill it before any upload.
  static Future<void> _ensureVocabularyData(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info("vocabulary")');
    final hasData = columns.any((column) => column['name'] == 'data');
    if (!hasData) {
      await db.execute(
        "ALTER TABLE vocabulary ADD COLUMN data TEXT NOT NULL DEFAULT '{}'",
      );
    }
    await db.rawUpdate("UPDATE vocabulary SET data = '{}' WHERE data IS NULL");
  }

  /// Remote schemas can gain optional fields between app releases. SQLite
  /// permits additive columns, so preserve those values instead of failing a
  /// local sync from an older database.
  static Future<void> ensureColumns(
    Database db,
    String table,
    Iterable<String> columns,
  ) async {
    _validateIdentifier(table);
    final existing = await db.rawQuery('PRAGMA table_info("$table")');
    final names = existing.map((row) => row['name'] as String).toSet();
    for (final column in columns.toSet()) {
      if (names.contains(column)) continue;
      _validateIdentifier(column);
      await db.execute('ALTER TABLE "$table" ADD COLUMN "$column"');
      names.add(column);
    }
  }

  static void _validateIdentifier(String value) {
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value)) {
      throw ArgumentError.value(value, 'identifier');
    }
  }

  static const _statements = [
    '''CREATE TABLE IF NOT EXISTS exams (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT,
      duration_minutes INTEGER, is_published INTEGER, audio_name TEXT,
      full_audio_url TEXT, srt_chunks TEXT, created_at TEXT, updated_at TEXT,
      user_id TEXT, dirty INTEGER NOT NULL DEFAULT 1
    )''',
    '''CREATE TABLE IF NOT EXISTS exam_contexts (
      id TEXT PRIMARY KEY, exam_id TEXT NOT NULL, part INTEGER,
      context_type TEXT, content TEXT, "index" INTEGER, additional_meta TEXT,
      created_at TEXT, updated_at TEXT, user_id TEXT,
      dirty INTEGER NOT NULL DEFAULT 1
    )''',
    '''CREATE TABLE IF NOT EXISTS exam_questions (
      id TEXT PRIMARY KEY, context_id TEXT NOT NULL, question_number INTEGER,
      question_type TEXT, content TEXT, options TEXT, correct_answer TEXT,
      additional_meta TEXT, created_at TEXT, updated_at TEXT, user_id TEXT,
      dirty INTEGER NOT NULL DEFAULT 1
    )''',
    '''CREATE TABLE IF NOT EXISTS user_question_tags (
      id TEXT PRIMARY KEY, context_id TEXT NOT NULL, tag_name TEXT NOT NULL,
      created_at TEXT, updated_at TEXT, user_id TEXT,
      dirty INTEGER NOT NULL DEFAULT 1
    )''',
    '''CREATE TABLE IF NOT EXISTS vocabulary (
      id TEXT PRIMARY KEY, context_id TEXT, word TEXT, meaning TEXT,
      source_text TEXT, status INTEGER, ord INTEGER, additional_meta TEXT,
      due_at TEXT, stability REAL, difficulty REAL,
      schedule_days INTEGER, reps INTEGER, lapses INTEGER, state INTEGER,
      step INTEGER, last_reviewed_at TEXT, last_rating INTEGER,
      sentence TEXT, sentence_translation TEXT,
      data TEXT NOT NULL DEFAULT '{}',
      created_at TEXT, updated_at TEXT, user_id TEXT,
      dirty INTEGER NOT NULL DEFAULT 1
    )''',
    '''CREATE TABLE IF NOT EXISTS exam_attempts (
      id TEXT PRIMARY KEY, exam_id TEXT NOT NULL, total_correct INTEGER,
      total_questions INTEGER, final_score REAL, duration_seconds INTEGER,
      additional_meta TEXT, created_at TEXT, updated_at TEXT, user_id TEXT,
      dirty INTEGER NOT NULL DEFAULT 1
    )''',
    '''CREATE TABLE IF NOT EXISTS user_answers (
      id TEXT PRIMARY KEY, attempt_id TEXT NOT NULL, question_id TEXT NOT NULL,
      user_choice TEXT, is_correct INTEGER, created_at TEXT, updated_at TEXT,
      user_id TEXT, dirty INTEGER NOT NULL DEFAULT 1
    )''',
    '''CREATE TABLE IF NOT EXISTS agent_requests (
      id TEXT PRIMARY KEY, exam_id TEXT NOT NULL, part INTEGER NOT NULL,
      prompt TEXT NOT NULL, status TEXT NOT NULL, error TEXT,
      attempts INTEGER NOT NULL DEFAULT 0, response_path TEXT,
      created_at TEXT NOT NULL, updated_at TEXT
    )''',
    '''CREATE TABLE IF NOT EXISTS exam_srt_chunks (
      id TEXT PRIMARY KEY, exam_id TEXT NOT NULL, "index" INTEGER,
      start_time REAL, end_time REAL, text TEXT, hint TEXT, note TEXT,
      additional_meta TEXT, created_at TEXT, updated_at TEXT, user_id TEXT,
      dirty INTEGER NOT NULL DEFAULT 1
    )''',
    '''CREATE TABLE IF NOT EXISTS mediafiles (
      id TEXT PRIMARY KEY, filename TEXT NOT NULL, updated_at TEXT NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0, user_id TEXT, created_at TEXT NOT NULL,
      dirty INTEGER NOT NULL DEFAULT 1
    )''',
    '''CREATE TABLE IF NOT EXISTS config (
      id TEXT PRIMARY KEY, key_name TEXT NOT NULL, value TEXT NOT NULL,
      created_at TEXT, updated_at TEXT, user_id TEXT,
      dirty INTEGER NOT NULL DEFAULT 1
    )''',
  ];

  static const _vocabularyColumns = [
    'schedule_days',
    'reps',
    'lapses',
    'state',
    'step',
    'last_reviewed_at',
    'last_rating',
    'sentence',
    'sentence_translation',
  ];
}
