import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config.dart';
import 'cloudflare_r2_service.dart';
import 'local_database.dart';
import 'local_schema_service.dart';
import 'uuid.dart';

typedef SyncProgress = void Function(String message);

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
    'config',
  ];
  // The deployed JunEdu Supabase schema predates this local-only field.
  static const _unsupportedRemoteColumns = {
    'exam_attempts': {'additional_meta'},
  };
  bool _ready = false;
  bool get isReady => _ready;

  Future<void> initialize() async {
    if (_ready || !AppConfig.hasSupabase) return;
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseKey,
    );
    _ready = true;
  }

  Future<String> syncToRemote({SyncProgress? onProgress}) async {
    onProgress?.call('Preparing local data...');
    await initialize();
    if (!_ready) return 'Supabase is not configured for this build.';
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return 'Sign in to Supabase before syncing.';
    final db = await LocalDatabase.instance.database;
    await _repairPendingIdentifiers(db);
    await _uploadTagDependencies(db, client, userId);
    onProgress?.call('Syncing media to Cloudflare R2...');
    final uploadedMedia = await _syncDirtyMediafiles(
      db,
      client,
      userId,
      onProgress: onProgress,
    );
    var uploaded = 0;
    var skippedOrphanTags = 0;
    for (final table in _tables) {
      onProgress?.call('Syncing $table data...');
      var dirty = await db.query(table, where: 'dirty = 1');
      if (table == 'user_question_tags') {
        final validTags = await _filterTagsWithLocalContexts(db, dirty);
        skippedOrphanTags += dirty.length - validTags.length;
        dirty = validTags;
      }
      if (dirty.isNotEmpty) {
        final payload = _remotePayload(table, dirty, userId);
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
    final skipped = skippedOrphanTags == 0
        ? ''
        : ' Skipped $skippedOrphanTags tags whose contexts no longer exist.';
    onProgress?.call('Sync complete.');
    return 'Synced $uploaded local records and $uploadedMedia media files.$skipped';
  }

  /// Tags reference contexts, which in turn reference exams. A context can be
  /// clean locally while still missing from a newly provisioned remote account,
  /// so upload those ancestors before any dirty tags.
  Future<void> _uploadTagDependencies(
    Database db,
    SupabaseClient client,
    String userId,
  ) async {
    final tags = await db.query(
      'user_question_tags',
      columns: ['context_id'],
      where: 'dirty = 1',
    );
    final contextIds = tags
        .map((row) => row['context_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    if (contextIds.isEmpty) return;

    final contexts = await _rowsByIds(db, 'exam_contexts', contextIds);
    final examIds = contexts
        .map((row) => row['exam_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    final exams = await _rowsByIds(db, 'exams', examIds);
    await _upsertRows(client, 'exams', exams, userId);
    await _upsertRows(client, 'exam_contexts', contexts, userId);
  }

  Future<int> _syncDirtyMediafiles(
    Database db,
    SupabaseClient client,
    String userId, {
    SyncProgress? onProgress,
  }) async {
    final mediafiles = await db.query('mediafiles', where: 'dirty = 1');
    var uploaded = 0;
    for (var index = 0; index < mediafiles.length; index++) {
      onProgress?.call(
        'Uploading media ${index + 1} of ${mediafiles.length}...',
      );
      final mediafile = mediafiles[index];
      final filename = mediafile['filename'] as String? ?? '';
      if (filename.isEmpty) continue;
      final isDeleted = (mediafile['is_deleted'] as num?)?.toInt() == 1;
      if (!isDeleted) {
        final localFile = CloudflareR2Service.instance.localFile(filename);
        if (!await localFile.exists()) continue;
        await CloudflareR2Service.instance.upload(localFile, userId, filename);
      }
      await _upsertMediafile(client, mediafile, userId);
      await db.update(
        'mediafiles',
        {'dirty': 0, 'user_id': userId},
        where: 'id = ?',
        whereArgs: [mediafile['id']],
      );
      uploaded++;
    }
    return uploaded;
  }

  Future<List<Map<String, Object?>>> _rowsByIds(
    Database db,
    String table,
    List<String> ids,
  ) async {
    if (ids.isEmpty) return [];
    final placeholders = List.filled(ids.length, '?').join(',');
    return db.query(table, where: 'id IN ($placeholders)', whereArgs: ids);
  }

  /// Matches JunEdu desktop sync: stale tags are kept locally but never sent
  /// when their context has been deleted, preventing a remote FK violation.
  Future<List<Map<String, Object?>>> _filterTagsWithLocalContexts(
    Database db,
    List<Map<String, Object?>> tags,
  ) async {
    final contextIds = tags
        .map((row) => row['context_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    final contexts = await _rowsByIds(db, 'exam_contexts', contextIds);
    final existingIds = contexts.map((row) => row['id'] as String).toSet();
    return tags
        .where((tag) => existingIds.contains(tag['context_id']))
        .toList();
  }

  Future<void> _upsertRows(
    SupabaseClient client,
    String table,
    List<Map<String, Object?>> rows,
    String userId,
  ) async {
    if (rows.isEmpty) return;
    final payload = _remotePayload(table, rows, userId);
    await client
        .schema(AppConfig.supabaseSchema)
        .from(table)
        .upsert(payload, onConflict: 'id');
  }

  /// Media records are identified remotely by both owner and filename. A
  /// device can assign a different local UUID to the same file, so using the
  /// generic primary-key conflict target would attempt a duplicate insert.
  Future<void> _upsertMediafile(
    SupabaseClient client,
    Map<String, Object?> mediafile,
    String userId,
  ) async {
    final payload = _remotePayload('mediafiles', [mediafile], userId);
    await client
        .schema(AppConfig.supabaseSchema)
        .from('mediafiles')
        .upsert(payload, onConflict: 'user_id,filename');
  }

  List<Map<String, Object?>> _remotePayload(
    String table,
    List<Map<String, Object?>> rows,
    String userId,
  ) {
    final unsupportedColumns = _unsupportedRemoteColumns[table] ?? const {};
    return rows.map((row) {
      final payload = <String, Object?>{...row, 'user_id': userId};
      payload.remove('dirty');
      for (final column in unsupportedColumns) {
        payload.remove(column);
      }
      if (table == 'vocabulary') {
        // Supabase requires a JSON object here. SQLite stores JSON as text,
        // and older rows may not have the column yet.
        payload['data'] = _jsonObject(payload['data']);
      }
      return payload;
    }).toList();
  }

  Map<String, Object?> _jsonObject(Object? value) {
    if (value is Map) return Map<String, Object?>.from(value);
    if (value is! String || value.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(value);
      return decoded is Map ? Map<String, Object?>.from(decoded) : {};
    } on FormatException {
      return {};
    }
  }

  Future<void> _repairPendingIdentifiers(Database db) =>
      db.transaction((tx) async {
        await _replaceInvalidIds(
          tx,
          'exam_contexts',
          children: const [
            (table: 'exam_questions', column: 'context_id'),
            (table: 'user_question_tags', column: 'context_id'),
            (table: 'vocabulary', column: 'context_id'),
          ],
        );
        await _replaceInvalidIds(
          tx,
          'exam_questions',
          children: const [(table: 'user_answers', column: 'question_id')],
        );
        await _replaceInvalidIds(
          tx,
          'exam_attempts',
          children: const [(table: 'user_answers', column: 'attempt_id')],
        );
        await _replaceInvalidIds(tx, 'user_answers');
        await _replaceInvalidIds(tx, 'user_question_tags');
      });

  Future<void> _replaceInvalidIds(
    Transaction tx,
    String table, {
    List<({String table, String column})> children = const [],
  }) async {
    final rows = await tx.query(table, columns: ['id']);
    for (final row in rows) {
      final oldId = row['id'] as String?;
      if (oldId == null || isUuid(oldId)) continue;
      final newId = newUuid();
      for (final child in children) {
        await tx.update(
          child.table,
          {child.column: newId, 'dirty': 1},
          where: '${child.column} = ?',
          whereArgs: [oldId],
        );
      }
      await tx.update(
        table,
        {'id': newId, 'dirty': 1},
        where: 'id = ?',
        whereArgs: [oldId],
      );
    }
  }

  Future<String> syncToLocal({SyncProgress? onProgress}) async {
    onProgress?.call('Preparing local storage...');
    await initialize();
    if (!_ready) return 'Supabase is not configured for this build.';
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return 'Sign in to Supabase before syncing.';
    final db = await LocalDatabase.instance.database;
    onProgress?.call('Downloading media from Cloudflare R2...');
    final downloadedMedia = await _syncMediafilesToLocal(
      db,
      client,
      userId,
      onProgress: onProgress,
    );
    var downloaded = 0;
    for (final table in _tables) {
      onProgress?.call('Downloading $table data...');
      final remote = await client
          .schema(AppConfig.supabaseSchema)
          .from(table)
          .select()
          .eq('user_id', userId);
      await LocalSchemaService.ensureColumns(
        db,
        table,
        remote.expand((row) => row.keys),
      );
      for (final row in remote) {
        await db.insert(
          table,
          _localPayload(row),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        downloaded++;
      }
    }
    onProgress?.call('Sync complete.');
    return 'Synced $downloaded cloud records and $downloadedMedia media files to local storage.';
  }

  Future<int> _syncMediafilesToLocal(
    Database db,
    SupabaseClient client,
    String userId, {
    SyncProgress? onProgress,
  }) async {
    final remote = await client
        .schema(AppConfig.supabaseSchema)
        .from('mediafiles')
        .select()
        .eq('user_id', userId);
    await LocalSchemaService.ensureColumns(
      db,
      'mediafiles',
      remote.expand((row) => row.keys),
    );
    var downloaded = 0;
    for (var index = 0; index < remote.length; index++) {
      onProgress?.call('Downloading media ${index + 1} of ${remote.length}...');
      final row = remote[index];
      final filename = row['filename'] as String? ?? '';
      final isDeleted = row['is_deleted'] == true || row['is_deleted'] == 1;
      if (filename.isNotEmpty && !isDeleted) {
        final localFile = CloudflareR2Service.instance.localFile(filename);
        if (!await localFile.exists()) {
          await CloudflareR2Service.instance.download(
            localFile,
            userId,
            filename,
          );
          downloaded++;
        }
      }
      await db.insert(
        'mediafiles',
        _localPayload(row),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    return downloaded;
  }

  /// Supabase decodes PostgreSQL booleans as Dart bools, while sqflite only
  /// accepts SQLite-compatible scalar values. JSON columns are decoded as
  /// maps/lists too, and must be encoded before insertion.
  Map<String, Object?> _localPayload(Map<String, dynamic> row) => {
    for (final entry in row.entries) entry.key: _sqliteValue(entry.value),
    'dirty': 0,
  };

  Object? _sqliteValue(Object? value) => switch (value) {
    bool value => value ? 1 : 0,
    Map() || List() => jsonEncode(value),
    _ => value,
  };
}
