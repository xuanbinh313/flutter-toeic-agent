import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../config.dart';
import '../features/import_questions/import_questions_agent_prompts.dart';
import '../features/import_questions/import_part_store.dart';
import 'local_database.dart';
import 'part_one_image_splitter.dart';

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
      final partOneImages =
          input.part == 1 &&
              input.questionPdf.isNotEmpty &&
              input.questionPages.isNotEmpty
          ? await PartOneImageSplitter().splitPdfPages(
              input.questionPdf,
              input.questionPages,
            )
          : const <String>[];
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
      _applyPartOneImages(contexts, partOneImages);
      await ImportPartStore(
        await LocalDatabase.instance.database,
      ).replace(examId: examId, part: input.part, contexts: contexts);
      request.status = 'succeeded';
      onProgress?.call('Replaced Part ${input.part} groups and questions.');
    } catch (error) {
      request.status = 'failed';
      request.error = '$error';
      rethrow;
    }
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

  List<Map<String, dynamic>> _parseContexts(String raw, int selectedPart) {
    final cleaned = raw
        .replaceAll(RegExp(r'^```(?:json)?\s*|\s*```$', multiLine: true), '')
        .trim();
    final decoded = jsonDecode(cleaned);
    final rows = decoded is List ? decoded : (decoded as Map)['contexts'];
    if (rows is! List) {
      throw const FormatException('Response has no contexts array.');
    }
    if (rows.isEmpty || rows.any((row) => row is! Map)) {
      throw const FormatException('Response has no valid contexts to import.');
    }
    return rows.whereType<Map>().map((row) {
      final value = Map<String, dynamic>.from(row);
      value['part'] = selectedPart;
      return value;
    }).toList();
  }

  void _applyPartOneImages(
    List<Map<String, dynamic>> contexts,
    List<String> imagePaths,
  ) {
    if (imagePaths.isEmpty) {
      return;
    }
    for (var index = 0; index < imagePaths.length; index++) {
      final context = index < contexts.length
          ? contexts[index]
          : <String, dynamic>{
              'part': 1,
              'context_type': 'IMAGE_DIAGRAM',
              'content': <String, dynamic>{},
              'additional_meta': <String, dynamic>{'note': ''},
              'questions': <Map<String, dynamic>>[],
            };
      if (index >= contexts.length) {
        contexts.add(context);
      }
      context['part'] = 1;
      context['context_type'] = 'IMAGE_DIAGRAM';
      final content = Map<String, dynamic>.from(
        context['content'] as Map? ?? {},
      );
      content['image_path'] = imagePaths[index];
      content['image_filename'] = path.basename(imagePaths[index]);
      context['content'] = content;
      final questions = context['questions'] as List? ?? <dynamic>[];
      if (questions.isEmpty) {
        questions.add({
          'question_number': index + 1,
          'question_type': 'MULTIPLE_CHOICE',
          'content':
              'Look at the picture and choose the statement that best describes it.',
          'options': <String>['', '', '', ''],
          'correct_answer': '',
          'additional_meta': <String, dynamic>{'note': ''},
        });
      }
      context['questions'] = questions;
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
