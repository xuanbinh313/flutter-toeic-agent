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
        (row['sentence'] as String?) ?? '',
        (row['sentence_translation'] as String?) ?? '',
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

  static Future<void> saveDetails({
    required String id,
    required String word,
    required String meaning,
    required String source,
  }) async {
    if (word.trim().isEmpty) {
      throw ArgumentError('Vocabulary word cannot be empty.');
    }
    final count = await (await LocalDatabase.instance.database).update(
      'vocabulary',
      {
        'word': word.trim(),
        'meaning': meaning.trim(),
        'source_text': source.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (count != 1) throw StateError('Vocabulary entry no longer exists.');
  }

  static Future<void> saveMeanings(Map<String, String> meanings) async {
    if (meanings.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final db = await LocalDatabase.instance.database;
    await db.transaction((transaction) async {
      for (final entry in meanings.entries) {
        await transaction.update(
          'vocabulary',
          {'meaning': entry.value, 'updated_at': now, 'dirty': 1},
          where: 'id = ?',
          whereArgs: [entry.key],
        );
      }
    });
  }

  static Future<void> saveSentences(
    Map<String, ({String sentence, String translation})> sentences,
  ) async {
    if (sentences.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final db = await LocalDatabase.instance.database;
    await db.transaction((transaction) async {
      for (final entry in sentences.entries) {
        await transaction.update(
          'vocabulary',
          {
            'sentence': entry.value.sentence,
            'sentence_translation': entry.value.translation,
            'updated_at': now,
            'dirty': 1,
          },
          where: 'id = ?',
          whereArgs: [entry.key],
        );
      }
    });
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
