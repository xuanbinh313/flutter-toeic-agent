import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LocalDatabasePathResolver {
  const LocalDatabasePathResolver._();

  static Future<String> resolve(String configuredPath) async {
    if (configuredPath.isNotEmpty) return configuredPath;
    final appDirectory = await getApplicationSupportDirectory();
    final appDatabase = path.join(appDirectory.path, 'exams.db');
    final projectDatabase = path.join(Directory.current.path, 'exams.db');
    if (await _hasExams(appDatabase)) return appDatabase;
    if (await _hasExams(projectDatabase)) return projectDatabase;
    if (File(appDatabase).existsSync()) return appDatabase;
    if (File(projectDatabase).existsSync()) return projectDatabase;
    return appDatabase;
  }

  static Future<bool> _hasExams(String databasePath) async {
    if (!File(databasePath).existsSync()) return false;
    Database? database;
    try {
      database = await databaseFactory.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final tables = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'exams'",
      );
      if (tables.isEmpty) return false;
      final rows = await database.rawQuery(
        'SELECT COUNT(*) AS count FROM exams',
      );
      final count = (rows.first['count'] as num?)?.toInt() ?? 0;
      return count > 0;
    } catch (_) {
      return false;
    } finally {
      await database?.close();
    }
  }
}
