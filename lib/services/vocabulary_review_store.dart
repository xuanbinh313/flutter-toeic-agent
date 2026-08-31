import 'dart:convert';

import '../models.dart';
import 'local_database.dart';

class VocabularyReviewStore {
  VocabularyReviewStore._();

  static Future<List<Vocab>> load() async {
    final rows = await (await LocalDatabase.instance.database).query(
      'vocabulary',
      orderBy: 'ord ASC, word COLLATE NOCASE',
    );
    return rows.map((row) {
      final schedule = _jsonMap(row['additional_meta']);
      return Vocab(
        row['word'] as String,
        (row['meaning'] as String?) ?? '',
        (row['source_text'] as String?) ?? '',
        (row['status'] as num?)?.toInt() ?? 1,
        row['id'] as String,
        _date(row['due_at']),
        _double(row['stability'], schedule['stability']),
        _double(row['difficulty'], schedule['difficulty']),
        _int(row['reps'], schedule['reps']),
        _int(row['lapses'], schedule['lapses']),
        _intOrNull(row['state'], schedule['state']),
        _intOrNull(row['step'], schedule['step']),
        _date(row['last_reviewed_at'] ?? schedule['last_reviewed_at']),
        _intOrNull(row['last_rating'], schedule['last_rating']),
      );
    }).toList();
  }

  static Future<void> save(Vocab word) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final schedule = <String, Object?>{
      'reps': word.reps,
      'lapses': word.lapses,
      'state': word.state,
      'step': word.step,
      'last_reviewed_at': word.lastReviewedAt?.toUtc().toIso8601String(),
      'last_rating': word.lastRating,
      'stability': word.stability,
      'difficulty': word.difficulty,
    };
    await (await LocalDatabase.instance.database).update(
      'vocabulary',
      {
        'due_at': word.dueAt?.toUtc().toIso8601String(),
        'stability': word.stability,
        'difficulty': word.difficulty,
        'schedule_days': word.dueAt?.difference(DateTime.now().toUtc()).inDays,
        'reps': word.reps,
        'lapses': word.lapses,
        'state': word.state,
        'step': word.step,
        'last_reviewed_at': word.lastReviewedAt?.toUtc().toIso8601String(),
        'last_rating': word.lastRating,
        'additional_meta': jsonEncode(schedule),
        'updated_at': now,
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [word.id],
    );
  }

  static Map<String, dynamic> _jsonMap(Object? value) {
    if (value is! String) return {};
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : {};
    } on FormatException {
      return {};
    }
  }

  static DateTime? _date(Object? value) => value is String
      ? DateTime.tryParse(value)?.toUtc()
      : value is num
      ? DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true)
      : null;

  static double? _double(Object? value, Object? fallback) =>
      (value ?? fallback) is num
      ? ((value ?? fallback) as num).toDouble()
      : null;

  static int _int(Object? value, Object? fallback) =>
      ((value ?? fallback) as num?)?.toInt() ?? 0;

  static int? _intOrNull(Object? value, Object? fallback) =>
      ((value ?? fallback) as num?)?.toInt();
}
