import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models.dart';

class AudioAnalysis {
  const AudioAnalysis({required this.taskId, required this.text});

  final String taskId;
  final String text;
}

class AlignedAudioImport {
  const AlignedAudioImport({required this.audioPath, required this.chunks});

  final String audioPath;
  final List<SrtChunk> chunks;
}

class ExternalAudioImportService {
  ExternalAudioImportService._();
  static final instance = ExternalAudioImportService._();

  String get _baseUrl => AppConfig.ttsAgentUrl.replaceFirst(RegExp(r'/$'), '');

  Future<AudioAnalysis> analyze(
    String audioPath,
    ValueChanged<String> progress,
  ) async {
    _validateConfig();
    progress('Uploading audio for extraction...');
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/api/extract-text'),
    );
    request.files.add(await http.MultipartFile.fromPath('audio', audioPath));
    final response = await http.Response.fromStream(await request.send());
    _ensureSuccess(response, 'start audio extraction');
    final taskId =
        (jsonDecode(response.body) as Map<String, dynamic>)['task_id']
            as String?;
    if (taskId == null || taskId.isEmpty) {
      throw const FormatException(
        'The audio service did not return a task id.',
      );
    }
    final result = await _poll(taskId, progress);
    return AudioAnalysis(taskId: taskId, text: result['text'] as String? ?? '');
  }

  Future<AlignedAudioImport> importAligned({
    required String sourcePath,
    required String taskId,
    required String text,
    required ValueChanged<String> progress,
  }) async {
    _validateConfig();
    if (text.trim().isEmpty) {
      throw const FormatException('Transcript text is required.');
    }
    progress('Sending transcript for audio alignment...');
    final response = await http.post(
      Uri.parse('$_baseUrl/api/align-audio'),
      body: {'task_id': taskId, 'text': text},
    );
    _ensureSuccess(response, 'start audio alignment');
    final alignmentTask =
        (jsonDecode(response.body) as Map<String, dynamic>)['task_id']
            as String?;
    if (alignmentTask == null || alignmentTask.isEmpty) {
      throw const FormatException(
        'The audio service did not return an alignment task id.',
      );
    }
    final result = await _poll(alignmentTask, progress);
    progress('Downloading aligned audio...');
    final rawUrl = result['url_audio'] as String? ?? '';
    if (rawUrl.isEmpty) {
      throw const FormatException(
        'The audio service did not return aligned audio.',
      );
    }
    final url = rawUrl.startsWith('http') ? rawUrl : '$_baseUrl$rawUrl';
    final audioResponse = await http.get(Uri.parse(url));
    _ensureSuccess(audioResponse, 'download aligned audio');
    final audioPath = await _saveAudio(sourcePath, audioResponse.bodyBytes);
    final chunks = _chunks(result);
    progress('Alignment complete: ${chunks.length} transcript chunks.');
    return AlignedAudioImport(audioPath: audioPath, chunks: chunks);
  }

  Future<Map<String, dynamic>> _poll(
    String taskId,
    ValueChanged<String> progress,
  ) async {
    for (var attempts = 0; attempts < 300; attempts++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      progress('Processing audio...');
      final response = await http.get(
        Uri.parse('$_baseUrl/api/check-status/$taskId'),
      );
      _ensureSuccess(response, 'check task status');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      switch (data['status']) {
        case 'completed':
          return (data['result'] as Map?)?.cast<String, dynamic>() ?? {};
        case 'failed':
          throw HttpException('${data['error'] ?? 'The audio task failed.'}');
      }
    }
    throw const HttpException('The audio task timed out.');
  }

  Future<String> _saveAudio(String sourcePath, List<int> bytes) async {
    final appData = Platform.environment['APPDATA'];
    if (appData == null) {
      throw const FileSystemException('APPDATA is not available.');
    }
    final folder = Directory('$appData${Platform.pathSeparator}jun-toeic');
    await folder.create(recursive: true);
    final sourceName = sourcePath
        .split(RegExp(r'[\\/]'))
        .last
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final target = File(
      '${folder.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}_$sourceName',
    );
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  List<SrtChunk> _chunks(Map<String, dynamic> result) {
    final raw = result['segments'] ?? result['content'];
    if (raw is! List) return [];
    return [
      for (var i = 0; i < raw.length; i++)
        if (raw[i] is Map)
          SrtChunk(
            id: '${DateTime.now().microsecondsSinceEpoch}-$i',
            index: i,
            start: _number(raw[i]['start'] ?? raw[i]['start_time']),
            end: _number(raw[i]['end'] ?? raw[i]['end_time']),
            text: raw[i]['text'] as String? ?? '',
            hint: raw[i]['hint'] as String? ?? raw[i]['note'] as String?,
          ),
    ];
  }

  double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  void _validateConfig() {
    if (_baseUrl.isEmpty) {
      throw StateError(
        'Set TTS_AGENT_URL in .env for development or with --dart-define for production.',
      );
    }
  }

  void _ensureSuccess(http.Response response, String action) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Could not $action (${response.statusCode}).');
    }
  }
}

typedef ValueChanged<T> = void Function(T value);
