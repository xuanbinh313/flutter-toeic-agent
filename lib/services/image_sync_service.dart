import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'cloudflare_r2_service.dart';
import 'local_mediafile_service.dart';

class ImageSyncService {
  ImageSyncService._();

  static final instance = ImageSyncService._();

  /// Moves referenced images to R2's local folder and queues them for upload.
  Future<void> prepareContextImagesForUpload(Database db) async {
    final rows = await db.query('exam_contexts', columns: ['id', 'content']);
    final now = DateTime.now().toUtc().toIso8601String();
    for (final row in rows) {
      final contextId = row['id'] as String?;
      final content = _jsonObject(row['content']);
      final imagePath = content['image_path'] as String?;
      if (contextId == null || imagePath == null || imagePath.isEmpty) continue;

      final oldFilename = content['image_filename'] as String?;
      final source = File(imagePath);
      final fallback = oldFilename == null || oldFilename.isEmpty
          ? null
          : CloudflareR2Service.instance.localFile(oldFilename);
      final sourceFile = await source.exists()
          ? source
          : fallback != null && await fallback.exists()
          ? fallback
          : null;
      if (sourceFile == null) continue;

      final extension = path.extension(sourceFile.path).isEmpty
          ? '.png'
          : path.extension(sourceFile.path);
      final safeContextId = contextId.replaceAll(
        RegExp(r'[^A-Za-z0-9_-]'),
        '_',
      );
      final filename = 'context_$safeContextId$extension';
      final targetPath = await LocalMediafileService.instance.copyToSyncStorage(
        sourceFile.path,
        filename: filename,
      );
      final sourcePath = path.canonicalize(imagePath);
      final localTargetPath = path.canonicalize(targetPath);
      final samePath = Platform.isWindows
          ? sourcePath.toLowerCase() == localTargetPath.toLowerCase()
          : sourcePath == localTargetPath;
      final changed = oldFilename != filename || !samePath;
      final mediaRows = await db.query(
        'mediafiles',
        columns: ['id', 'is_deleted'],
        where: 'filename = ?',
        whereArgs: [filename],
        limit: 1,
      );
      if (changed || mediaRows.isEmpty || mediaRows.first['is_deleted'] == 1) {
        await LocalMediafileService.instance.registerNew(targetPath);
      }
      if (changed) {
        content['image_filename'] = filename;
        content['image_path'] = targetPath;
        await db.update(
          'exam_contexts',
          {'content': jsonEncode(content), 'dirty': 1, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [contextId],
        );
      }
    }
  }

  /// Keeps absolute device paths out of Supabase JSON content.
  void prepareRemotePayload(Map<String, Object?> payload) {
    final content = _jsonObject(payload['content']);
    final imagePath = content['image_path'] as String?;
    final filename =
        content['image_filename'] as String? ??
        (imagePath == null || imagePath.isEmpty
            ? null
            : path.basename(imagePath));
    if (filename == null || filename.isEmpty) return;
    content['image_filename'] = filename;
    content.remove('image_path');
    payload['content'] = jsonEncode(content);
  }

  /// Resolves the portable remote image filename to this computer's R2 folder.
  void prepareLocalPayload(
    Map<String, dynamic> row,
    Map<String, Object?> payload,
  ) {
    final content = _jsonObject(row['content']);
    final imagePath = content['image_path'] as String?;
    final filename =
        content['image_filename'] as String? ??
        (imagePath == null || imagePath.isEmpty
            ? null
            : path.basename(imagePath));
    if (filename == null || filename.isEmpty) return;
    content['image_filename'] = filename;
    content['image_path'] = CloudflareR2Service.instance
        .localFile(filename)
        .path;
    payload['content'] = jsonEncode(content);
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
}
