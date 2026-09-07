import '../services/local_database.dart';
import 'uuid.dart';

class VocabularySentenceCache {
  VocabularySentenceCache._();

  static const _key = 'vocabulary_sentence_generation_date';

  static Future<bool> wasGeneratedToday() async {
    final rows = await (await LocalDatabase.instance.database).query(
      'config',
      columns: ['value'],
      where: 'key_name = ?',
      whereArgs: [_key],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return rows.isNotEmpty && rows.first['value'] == _today();
  }

  static Future<void> markGeneratedToday() async {
    final db = await LocalDatabase.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await db.query(
      'config',
      columns: ['id'],
      where: 'key_name = ?',
      whereArgs: [_key],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      await db.insert('config', {
        'id': newUuid(),
        'key_name': _key,
        'value': _today(),
        'created_at': now,
        'updated_at': now,
        'dirty': 1,
      });
      return;
    }
    await db.update(
      'config',
      {'value': _today(), 'updated_at': now, 'dirty': 1},
      where: 'id = ?',
      whereArgs: [rows.first['id']],
    );
  }

  static String _today() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}
