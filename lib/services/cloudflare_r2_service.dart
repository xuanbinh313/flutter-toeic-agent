import 'dart:io';

import 'package:minio/io.dart';
import 'package:minio/minio.dart';
import 'package:path/path.dart' as path;

import '../config.dart';

class CloudflareR2Service {
  CloudflareR2Service._();
  static final instance = CloudflareR2Service._();

  Future<void> upload(File localFile, String userId, String filename) async {
    _validateSettings();
    if (!await localFile.exists()) {
      throw FileSystemException(
        'Local media file does not exist.',
        localFile.path,
      );
    }
    await _client.fPutObject(
      _bucket,
      _objectKey(userId, filename),
      localFile.path,
    );
  }

  Future<void> download(File localFile, String userId, String filename) async {
    _validateSettings();
    await localFile.parent.create(recursive: true);
    // fGetObject calls statObject, which requests object ACLs by default.
    // Cloudflare R2 does not implement GetObjectAcl, so stream the object
    // directly instead.
    final temporary = File('${localFile.path}.download');
    if (await temporary.exists()) await temporary.delete();
    try {
      final stream = await _client.getObject(
        _bucket,
        _objectKey(userId, filename),
      );
      final sink = temporary.openWrite();
      await stream.pipe(sink);
      await temporary.copy(localFile.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  File localFile(String filename) {
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) {
      throw const FileSystemException('APPDATA is not available.');
    }
    return File(path.join(appData, 'jun-toeic', path.basename(filename)));
  }

  Minio get _client {
    final endpoint = AppConfig.r2Endpoint.trim();
    return Minio(
      endPoint: endpoint
          .replaceFirst(RegExp(r'^https?://'), '')
          .replaceFirst(RegExp(r'/$'), ''),
      accessKey: AppConfig.r2AccessKey,
      secretKey: AppConfig.r2SecretKey,
      useSSL: !endpoint.startsWith('http://'),
    );
  }

  String get _bucket => AppConfig.r2Bucket;

  String _objectKey(String userId, String filename) =>
      'media/$userId/${path.basename(filename)}';

  void _validateSettings() {
    if (!AppConfig.hasR2) {
      throw StateError('Cloudflare R2 is not configured for this build.');
    }
  }
}
