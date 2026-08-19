import 'dart:io';

import 'package:flutter/foundation.dart';

/// Build-time values are always preferred. During debug development only,
/// missing values are loaded from the untracked project `.env` file.
abstract final class AppConfig {
  static String _supabaseUrl = const String.fromEnvironment('SUPABASE_URL');
  static String _supabaseKey = const String.fromEnvironment('SUPABASE_KEY');
  static String _supabaseSchema = const String.fromEnvironment(
    'SUPABASE_SCHEMA',
    defaultValue: 'public',
  );
  static String _databasePath = const String.fromEnvironment('JUNEDU_DB_PATH');
  static String _geminiApiKey = const String.fromEnvironment('GEMINI_API_KEY');
  static String _geminiModel = const String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-2.5-flash',
  );
  static String _ttsAgentUrl = const String.fromEnvironment('TTS_AGENT_URL');
  static String _r2Endpoint = const String.fromEnvironment(
    'CLOUDFLARE_ENDPOINT',
  );
  static String _r2AccessKey = const String.fromEnvironment(
    'CLOUDFLARE_ACCESS_KEY',
  );
  static String _r2SecretKey = const String.fromEnvironment(
    'CLOUDFLARE_SECRET_KEY',
  );
  static String _r2Bucket = const String.fromEnvironment(
    'CLOUDFLARE_BUCKET_NAME',
  );

  static String get supabaseUrl => _supabaseUrl;
  static String get supabaseKey => _supabaseKey;
  static String get supabaseSchema => _supabaseSchema;
  static String get databasePath => _databasePath;
  static String get geminiApiKey => _geminiApiKey;
  static String get geminiModel => _geminiModel;
  static String get ttsAgentUrl => _ttsAgentUrl;
  static String get r2Endpoint => _r2Endpoint;
  static String get r2AccessKey => _r2AccessKey;
  static String get r2SecretKey => _r2SecretKey;
  static String get r2Bucket => _r2Bucket;
  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
  static bool get hasR2 =>
      r2Endpoint.isNotEmpty &&
      r2AccessKey.isNotEmpty &&
      r2SecretKey.isNotEmpty &&
      r2Bucket.isNotEmpty;

  /// Release builds never read `.env`; supply their values with `--dart-define`.
  static Future<void> initialize() async {
    if (!kDebugMode) return;
    final file = File('.env');
    if (!await file.exists()) return;
    final values = _parse(await file.readAsLines());
    _supabaseUrl = _supabaseUrl.isNotEmpty
        ? _supabaseUrl
        : values['SUPABASE_URL'] ?? '';
    _supabaseKey = _supabaseKey.isNotEmpty
        ? _supabaseKey
        : values['SUPABASE_KEY'] ?? '';
    _supabaseSchema = _supabaseSchema == 'public'
        ? values['SUPABASE_SCHEMA'] ?? _supabaseSchema
        : _supabaseSchema;
    _databasePath = _databasePath.isNotEmpty
        ? _databasePath
        : values['JUNEDU_DB_PATH'] ?? '';
    _geminiApiKey = _geminiApiKey.isNotEmpty
        ? _geminiApiKey
        : values['GEMINI_API_KEY'] ?? '';
    _geminiModel = _geminiModel == 'gemini-2.5-flash'
        ? values['GEMINI_MODEL'] ?? _geminiModel
        : _geminiModel;
    _ttsAgentUrl = _ttsAgentUrl.isNotEmpty
        ? _ttsAgentUrl
        : values['TTS_AGENT_URL'] ?? '';
    _r2Endpoint = _r2Endpoint.isNotEmpty
        ? _r2Endpoint
        : values['CLOUDFLARE_R2_ENDPOINT'] ??
              values['CLOUDFLARE_ENDPOINT'] ??
              '';
    _r2AccessKey = _r2AccessKey.isNotEmpty
        ? _r2AccessKey
        : values['CLOUDFLARE_R2_ACCESS_KEY_ID'] ??
              values['CLOUDFLARE_ACCESS_KEY_ID'] ??
              values['CLOUDFLARE_ACCESS_KEY'] ??
              '';
    _r2SecretKey = _r2SecretKey.isNotEmpty
        ? _r2SecretKey
        : values['CLOUDFLARE_R2_SECRET_ACCESS_KEY'] ??
              values['CLOUDFLARE_SECRET_ACCESS_KEY'] ??
              values['CLOUDFLARE_SECRET_KEY'] ??
              '';
    _r2Bucket = _r2Bucket.isNotEmpty
        ? _r2Bucket
        : values['CLOUDFLARE_R2_BUCKET'] ??
              values['CLOUDFLARE_BUCKET'] ??
              values['CLOUDFLARE_BUCKET_NAME'] ??
              '';
  }

  static Map<String, String> _parse(List<String> lines) {
    final values = <String, String>{};
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final separator = trimmed.indexOf('=');
      if (separator < 1) continue;
      final key = trimmed.substring(0, separator).trim();
      var value = trimmed.substring(separator + 1).trim();
      if (value.length > 1 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      values[key] = value;
    }
    return values;
  }
}
