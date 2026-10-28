import 'dart:io';

import 'package:path/path.dart' as path;

import 'cloudflare_r2_service.dart';
import 'local_database.dart';
import 'uuid.dart';

class LocalMediafileService {
  LocalMediafileService._();

  static final instance = LocalMediafileService._();

  /// Copies a local source into the directory used by the R2 sync service.
  Future<String> copyToSyncStorage(String localPath, {String? filename}) async {
    final source = File(localPath);
    if (!await source.exists()) {
      throw FileSystemException('Local media file does not exist.', localPath);
    }
    final target = CloudflareR2Service.instance.localFile(
      filename ?? path.basename(localPath),
    );
    await target.parent.create(recursive: true);
    final sourcePath = path.canonicalize(source.path);
    final targetPath = path.canonicalize(target.path);
    final samePath = Platform.isWindows
        ? sourcePath.toLowerCase() == targetPath.toLowerCase()
        : sourcePath == targetPath;
    if (!samePath) {
      await source.copy(target.path);
    }
    return target.path;
  }

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
