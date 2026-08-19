import 'package:path/path.dart' as path;

import 'local_database.dart';
import 'uuid.dart';

class LocalMediafileService {
  LocalMediafileService._();

  static final instance = LocalMediafileService._();

  /// Records a locally created media file so the next remote sync uploads it.
  Future<String> registerNew(String localPath) async {
    final filename = path.basename(localPath);
    if (filename.isEmpty) {
      throw const FormatException('A media file must have a filename.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final db = await LocalDatabase.instance.database;
    final existing = await db.query(
      'mediafiles',
      columns: ['id'],
      where: 'filename = ?',
      whereArgs: [filename],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('mediafiles', {
        'id': newUuid(),
        'filename': filename,
        'created_at': now,
        'updated_at': now,
        'is_deleted': 0,
        'dirty': 1,
      });
    } else {
      await db.update(
        'mediafiles',
        {'updated_at': now, 'is_deleted': 0, 'dirty': 1},
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
    return filename;
  }
}
