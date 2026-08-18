import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config.dart';
import 'local_database.dart';

class SyncService {
  SyncService._();
  static final instance = SyncService._();
  static const _tables = [
    'exams',
    'exam_contexts',
    'exam_questions',
    'user_question_tags',
    'vocabulary',
    'exam_attempts',
    'user_answers',
  ];
  bool _ready = false;

  Future<void> initialize() async {
    if (_ready || !AppConfig.hasSupabase) return;
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseKey,
    );
    _ready = true;
  }

  Future<String> sync() async {
    await initialize();
    if (!_ready) return 'Supabase is not configured for this build.';
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return 'Sign in to Supabase before syncing.';
    final db = await LocalDatabase.instance.database;
    var uploaded = 0;
    for (final table in _tables) {
      final dirty = await db.query(table, where: 'dirty = 1');
      if (dirty.isNotEmpty) {
        final payload = dirty
            .map((row) => {...row, 'user_id': userId}..remove('dirty'))
            .toList();
        await client
            .schema(AppConfig.supabaseSchema)
            .from(table)
            .upsert(payload, onConflict: 'id');
        final ids = dirty.map((row) => row['id'] as String).toList();
        final placeholders = List.filled(ids.length, '?').join(',');
        await db.rawUpdate(
          'UPDATE $table SET dirty = 0, user_id = ? WHERE id IN ($placeholders)',
          [userId, ...ids],
        );
        uploaded += ids.length;
      }
    }
    var downloaded = 0;
    for (final table in _tables) {
      final remote = await client
          .schema(AppConfig.supabaseSchema)
          .from(table)
          .select()
          .eq('user_id', userId);
      for (final row in remote) {
        await db.insert(table, {
          ...row,
          'dirty': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        downloaded++;
      }
    }
    return 'Synced $uploaded local and $downloaded cloud records.';
  }
}
