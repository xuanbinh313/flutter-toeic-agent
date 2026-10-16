import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../config.dart';
import '../features/import_questions/import_questions_agent_prompts.dart';
import '../features/import_questions/import_part_store.dart';
import 'local_database.dart';
import 'part_one_image_cropper.dart';
import 'part_one_agent_response.dart';
import 'uuid.dart';

class ImportPartInput {
  ImportPartInput(this.part) {
    contextText = part == 2 ? 'Mark your answer on your answer sheet' : '';
    prompt = ImportQuestionsAgentService.defaultPrompt(part);
  }

  final int part;
  String questionPdf = '';
  String transcriptPdf = '';
  List<int> questionPages = [];
  List<int> transcriptPages = [];
  String contextText = '';
  String prompt = '';

  bool get hasInput =>
      (part != 2 && questionPdf.isNotEmpty && questionPages.isNotEmpty) ||
      (transcriptPdf.isNotEmpty && transcriptPages.isNotEmpty);
}

class OverallPdfSource {
  String path = '';
  List<int> pages = [];
  String tempPath = '';

  bool get isSelected =>
      path.isNotEmpty && pages.isNotEmpty && tempPath.isNotEmpty;
}

class AgentRequest {
  AgentRequest({
    String? id,
    required this.part,
    required this.prompt,
    DateTime? createdAt,
  }) : id = id ?? newUuid(),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final int part;
  String prompt;
  String status = 'queued';
  String error = '';
  int attempts = 0;
  String responsePath = '';
  final DateTime createdAt;
}

class ImportQuestionsAgentService {
  ImportQuestionsAgentService(this.examId);

  final String examId;
  final parts = List.generate(7, (index) => ImportPartInput(index + 1));
  final sources = {
    'listening': {
      'questions': OverallPdfSource(),
      'transcripts': OverallPdfSource(),
    },
    'reading': {
      'questions': OverallPdfSource(),
      'transcripts': OverallPdfSource(),
    },
  };
  String listeningAnswerSheet = '';
  String readingAnswerSheet = '';
  final requests = <AgentRequest>[];

  static String defaultPrompt(int part) =>
      ImportQuestionsAgentPrompts.forPart(part);

  Future<void> loadRequests() async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      'agent_requests',
      where: 'exam_id = ?',
      whereArgs: [examId],
      orderBy: 'created_at ASC',
    );
    if (rows.isNotEmpty) {
      _setRequests(rows);
      return;
    }
    // Migrate the previous local JSON index once, if it exists.
    try {
      final file = await _requestsFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return;
      requests
        ..clear()
        ..addAll(
          decoded.whereType<Map>().map((value) {
            final request = AgentRequest(
              id: '${value['id'] ?? ''}'.isEmpty ? null : '${value['id']}',
              part: (value['part'] as num?)?.toInt() ?? 1,
              prompt: '${value['prompt'] ?? ''}',
              createdAt: DateTime.tryParse('${value['createdAt']}'),
            );
            request
              ..status = '${value['status'] ?? 'queued'}'
              ..error = '${value['error'] ?? ''}'
              ..attempts = (value['attempts'] as num?)?.toInt() ?? 0
              ..responsePath = kDebugMode
                  ? '${value['responsePath'] ?? ''}'
                  : '';
            if (request.status == 'running') {
              request
                ..status = 'failed'
                ..error = 'Request was interrupted before completion.';
            }
            return request;
          }),
        );
      await saveRequests();
    } catch (_) {
      // A missing/corrupt request index must not prevent importing.
    }
  }

  Future<void> saveRequests() async {
    final db = await LocalDatabase.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((tx) async {
      await tx.delete(
        'agent_requests',
        where: 'exam_id = ?',
        whereArgs: [examId],
      );
      for (final request in requests) {
        await tx.insert('agent_requests', {
          'id': request.id,
          'exam_id': examId,
          'part': request.part,
          'prompt': request.prompt,
          'status': request.status,
          'error': request.error,
          'attempts': request.attempts,
          'response_path': request.responsePath,
          'created_at': request.createdAt.toUtc().toIso8601String(),
          'updated_at': now,
        });
      }
    });
  }

  void _setRequests(List<Map<String, Object?>> rows) {
    requests
      ..clear()
      ..addAll(
        rows.map((value) {
          final request = AgentRequest(
            id: '${value['id']}',
            part: (value['part'] as num?)?.toInt() ?? 1,
            prompt: '${value['prompt'] ?? ''}',
            createdAt: DateTime.tryParse('${value['created_at']}'),
          );
          request
            ..status = '${value['status'] ?? 'queued'}'
            ..error = '${value['error'] ?? ''}'
            ..attempts = (value['attempts'] as num?)?.toInt() ?? 0
            ..responsePath = kDebugMode
                ? '${value['response_path'] ?? ''}'
                : '';
          if (request.status == 'running') {
            request
              ..status = 'failed'
              ..error = 'Request was interrupted before completion.';
          }
          return request;
        }),
      );
  }

  Future<File> _requestsFile() async {
    final directory = await getApplicationSupportDirectory();
    final safeExamId = examId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File(path.join(directory.path, 'agent_requests_$safeExamId.json'));
  }

  Future<String> prepareOverallSourcePdf({
    required String section,
    required String lane,
    required String sourcePath,
    required List<int> selectedPages,
  }) async {
    final document = PdfDocument(
      inputBytes: await File(sourcePath).readAsBytes(),
    );
    try {
      final pages = selectedPages.toSet();
      for (var index = document.pages.count - 1; index >= 0; index--) {
        if (!pages.contains(index)) {
          document.pages.removeAt(index);
        }
      }
      if (document.pages.count == 0) {
        throw StateError(
          'Selected pages are outside ${path.basename(sourcePath)}.',
        );
      }
      final directory = await getTemporaryDirectory();
      final target = File(
        path.join(
          directory.path,
          'junedu_${section}_${lane}_${DateTime.now().microsecondsSinceEpoch}.pdf',
        ),
      );
      await target.writeAsBytes(await document.save(), flush: true);
      return target.path;
    } finally {
      document.dispose();
    }
  }

  Future<List<AgentRequest>> send({
    void Function(String message)? onProgress,
  }) async {
    if (AppConfig.geminiApiKey.isEmpty) {
      throw StateError('GEMINI_API_KEY is missing from application config.');
    }
    final selected = parts.where((part) => part.hasInput).toList();
    if (selected.isEmpty) {
      throw StateError('Select pages for at least one part.');
    }
    final missingListening =
        selected.any((part) => part.part <= 4) && listeningAnswerSheet.isEmpty;
    final missingReading =
        selected.any((part) => part.part >= 5) && readingAnswerSheet.isEmpty;
    if (missingListening || missingReading) {
      final names = [
        if (missingListening) 'Listening',
        if (missingReading) 'Reading/Writing',
      ];
      throw StateError('Answer sheet required: ${names.join(', ')}.');
    }

    final failedRequests = <AgentRequest>[];
    for (final input in selected) {
      final request = AgentRequest(part: input.part, prompt: input.prompt);
      requests.add(request);
      try {
        await saveRequests();
        await _runRequest(request, input, onProgress: onProgress);
      } catch (error) {
        request
          ..status = 'failed'
          ..error = '$error';
        failedRequests.add(request);
        try {
          await saveRequests();
        } catch (_) {
          // Keep sending the remaining parts even if request persistence fails.
        }
        onProgress?.call(
          'Part ${input.part} failed. Continuing with the remaining parts...',
        );
      }
    }
    return failedRequests;
  }

  Future<void> retry(
    AgentRequest request, {
    void Function(String message)? onProgress,
  }) async {
    final input = parts[request.part - 1];
    if (!input.hasInput) throw StateError('Part ${request.part} has no input.');
    request.prompt = input.prompt;
    await _runRequest(request, input, onProgress: onProgress);
  }

  Future<void> _runRequest(
    AgentRequest request,
    ImportPartInput input, {
    void Function(String message)? onProgress,
  }) async {
    request.status = 'running';
    request.error = '';
    request.attempts++;
    await saveRequests();
    onProgress?.call('Preparing Part ${input.part}...');
    try {
      final parts = <Part>[TextPart(_promptFor(input))];
      if (input.questionPdf.isNotEmpty && input.questionPages.isNotEmpty) {
        parts.add(
          DataPart(
            'application/pdf',
            await _selectedPdfBytes(input.questionPdf, input.questionPages),
          ),
        );
      }
      if (input.transcriptPdf.isNotEmpty && input.transcriptPages.isNotEmpty) {
        parts.add(
          DataPart(
            'application/pdf',
            await _selectedPdfBytes(input.transcriptPdf, input.transcriptPages),
          ),
        );
      }
      final answerSheet = input.part <= 4
          ? listeningAnswerSheet
          : readingAnswerSheet;
      parts.add(
        DataPart(_mimeType(answerSheet), await File(answerSheet).readAsBytes()),
      );
      onProgress?.call('Sending Part ${input.part} to Gemini...');
      final model = GenerativeModel(
        model: AppConfig.geminiModel,
        apiKey: AppConfig.geminiApiKey,
        generationConfig: GenerationConfig(
          temperature: 0.1,
          responseMimeType: 'application/json',
        ),
      );
      final response = await model.generateContent([Content.multi(parts)]);
      final text = response.text;
      if (text == null || text.trim().isEmpty) {
        throw StateError('Gemini returned an empty response.');
      }
      if (kDebugMode) {
        request.responsePath = await _saveAgentResponse(input.part, text);
        onProgress?.call('Saved raw agent response: ${request.responsePath}');
      }
      final decoded = PartOneAgentResponse.decode(text);
      final contexts = PartOneAgentResponse.contexts(decoded, input.part);
      final partOneImages =
          input.part == 1 &&
              input.questionPdf.isNotEmpty &&
              input.questionPages.isNotEmpty
          ? await PartOneImageCropper().cropPdfRegions(
              input.questionPdf,
              input.questionPages,
              PartOneAgentResponse.imageRegions(decoded),
            )
          : const <String>[];
      PartOneAgentResponse.applyImages(contexts, partOneImages);
      await ImportPartStore(
        await LocalDatabase.instance.database,
      ).replace(examId: examId, part: input.part, contexts: contexts);
      request.status = 'succeeded';
      await saveRequests();
      onProgress?.call('Replaced Part ${input.part} groups and questions.');
    } catch (error) {
      request.status = 'failed';
      request.error = '$error';
      await saveRequests();
      rethrow;
    }
  }

  Future<String> _saveAgentResponse(int part, String response) async {
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final filename =
        'exam_${examId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}'
        '_part_${part}_$timestamp.json';
    final cleaned = response
        .replaceAll(RegExp(r'^```(?:json)?\s*|\s*```$', multiLine: true), '')
        .trim();
    Object jsonValue = cleaned;
    try {
      jsonValue = jsonDecode(cleaned);
    } on FormatException {
      // Keep the raw response available even when it is not valid JSON.
    }
    final contents = jsonValue is String
        ? jsonValue
        : const JsonEncoder.withIndent('  ').convert(jsonValue);
    final locations = <String>[];
    for (final directoryProvider in <Future<Directory> Function()>[
      getApplicationSupportDirectory,
      getApplicationDocumentsDirectory,
    ]) {
      try {
        final directory = await directoryProvider();
        locations.add(path.join(directory.path, 'agent_responses', filename));
      } catch (_) {
        // Try the next writable location.
      }
    }
    // Useful for development and portable builds; production normally uses
    // one of the OS-managed writable directories above.
    locations.add(
      path.join(Directory.current.path, 'agent_responses', filename),
    );
    Object? lastError;
    for (final location in locations) {
      try {
        final file = File(location);
        await file.parent.create(recursive: true);
        await file.writeAsString(contents, flush: true);
        return file.path;
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('Could not save agent response: $lastError');
  }

  String _promptFor(ImportPartInput input) =>
      '''${input.prompt}

Target TOEIC part: ${input.part}.
Extract ONLY TOEIC Part ${input.part}.
Return only the raw JSON object with contexts containing nested questions.
${ImportQuestionsAgentPrompts.noteContract}

Selected question PDF pages: ${_pages(input.questionPages)}.
Selected transcript PDF pages: ${_pages(input.transcriptPages)}.
${input.contextText.isEmpty ? '' : 'Default context text: ${input.contextText}'}
The attached source PDFs may contain other pages. Extract only the selected page
numbers and only TOEIC Part ${input.part}. The attached answer sheet determines
correct_answer. Return no markdown or explanation outside the JSON object.''';

  String _pages(List<int> pages) =>
      pages.isEmpty ? 'none' : pages.map((page) => page + 1).join(', ');

  Future<Uint8List> _selectedPdfBytes(String file, List<int> selected) async {
    final document = PdfDocument(inputBytes: await File(file).readAsBytes());
    try {
      final pageIndices = selected.toSet();
      for (var index = document.pages.count - 1; index >= 0; index--) {
        if (!pageIndices.contains(index)) {
          document.pages.removeAt(index);
        }
      }
      if (document.pages.count == 0) {
        throw StateError('Selected pages are outside ${path.basename(file)}.');
      }
      return Uint8List.fromList(await document.save());
    } finally {
      document.dispose();
    }
  }

  String _mimeType(String file) {
    final ext = path.extension(file).toLowerCase();
    return switch (ext) {
      '.pdf' => 'application/pdf',
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.webp' => 'image/webp',
      _ => 'application/octet-stream',
    };
  }
}
