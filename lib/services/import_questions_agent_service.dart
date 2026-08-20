import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:path/path.dart' as path;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../config.dart';
import '../models.dart';
import 'local_database.dart';

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

class AgentRequest {
  AgentRequest({required this.part, required this.prompt});

  final int part;
  String prompt;
  String status = 'queued';
  String error = '';
  int attempts = 0;
  final DateTime createdAt = DateTime.now();
}

class ImportQuestionsAgentService {
  ImportQuestionsAgentService(this.examId);

  final String examId;
  final parts = List.generate(7, (index) => ImportPartInput(index + 1));
  String listeningAnswerSheet = '';
  String readingAnswerSheet = '';
  final requests = <AgentRequest>[];

  static String defaultPrompt(int part) {
    final type = switch (part) {
      1 => 'IMAGE_DIAGRAM',
      2 => 'STANDALONE',
      3 || 4 => 'AUDIO_SRT',
      _ => 'READING_PASSAGE',
    };
    final range = switch (part) {
      1 => '1-10',
      2 => '11-40',
      3 => '41-70',
      4 => '71-100',
      5 => '101-130',
      6 => '131-146',
      _ => '147-200',
    };
    return '''Analyze ONLY TOEIC Part $part. Output only one raw JSON object.
Return {"contexts":[...]}; each context must have id, part, context_type,
content {"text":""}, index, additional_meta {"note":""}, and nested
questions. Each question needs question_number, question_type, content,
options, correct_answer, additional_meta {"note":""}.
Use natural Vietnamese in every non-empty note. Extract only questions $range.
Use context_type "$type" and do not include another TOEIC part.''';
  }

  Future<void> send({void Function(String message)? onProgress}) async {
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

    for (final input in selected) {
      final request = AgentRequest(part: input.part, prompt: input.prompt);
      requests.add(request);
      await _runRequest(request, input, onProgress: onProgress);
    }
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
      final contexts = _parseContexts(text, input.part);
      await _saveContexts(contexts);
      request.status = 'succeeded';
      onProgress?.call('Imported Part ${input.part}.');
    } catch (error) {
      request.status = 'failed';
      request.error = '$error';
      rethrow;
    }
  }

  String _promptFor(ImportPartInput input) =>
      '''${input.prompt}

Selected question PDF pages: ${_pages(input.questionPages)}.
Selected transcript PDF pages: ${_pages(input.transcriptPages)}.
${input.contextText.isEmpty ? '' : 'Default context text: ${input.contextText}'}
The attached source PDFs may contain other pages. Extract only the selected page
numbers and only TOEIC Part ${input.part}. The attached answer sheet determines
correct_answer. Return no markdown or explanation outside the JSON object.''';

  List<Map<String, dynamic>> _parseContexts(String raw, int selectedPart) {
    final cleaned = raw
        .replaceAll(RegExp(r'^```(?:json)?\s*|\s*```$', multiLine: true), '')
        .trim();
    final decoded = jsonDecode(cleaned);
    final rows = decoded is List ? decoded : (decoded as Map)['contexts'];
    if (rows is! List) {
      throw const FormatException('Response has no contexts array.');
    }
    return rows.whereType<Map>().map((row) {
      final value = Map<String, dynamic>.from(row);
      value['part'] = selectedPart;
      return value;
    }).toList();
  }

  Future<void> _saveContexts(List<Map<String, dynamic>> contexts) async {
    for (var index = 0; index < contexts.length; index++) {
      final context = contexts[index];
      final content = context['content'];
      final meta = context['additional_meta'];
      final questions = (context['questions'] as List? ?? []).whereType<Map>();
      final mapped = questions
          .map((question) {
            final item = Map<String, dynamic>.from(question);
            final questionMeta = item['additional_meta'] as Map?;
            return ExamQuestion(
              id: '',
              number: (item['question_number'] as num?)?.toInt() ?? 0,
              type: '${item['question_type'] ?? 'MULTIPLE_CHOICE'}'
                  .toUpperCase(),
              content: '${item['content'] ?? ''}',
              options: (item['options'] as List? ?? [])
                  .map((value) => '$value')
                  .toList(),
              correctAnswer: '${item['correct_answer'] ?? ''}'.toUpperCase(),
              note: '${questionMeta?['note'] ?? ''}',
            );
          })
          .where((question) => question.number > 0)
          .toList();
      await LocalDatabase.instance.saveContext(
        examId: examId,
        part: (context['part'] as num?)?.toInt() ?? 1,
        type: '${context['context_type'] ?? 'STANDALONE'}'.toUpperCase(),
        text: content is Map ? '${content['text'] ?? ''}' : '$content',
        note: meta is Map ? '${meta['note'] ?? ''}' : '',
        audioStart: meta is Map
            ? (meta['audio_start'] as num?)?.toDouble() ?? 0
            : 0,
        audioEnd: meta is Map
            ? (meta['audio_end'] as num?)?.toDouble() ?? 0
            : 0,
        questions: mapped,
      );
    }
  }

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
