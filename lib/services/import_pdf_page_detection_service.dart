import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';

import '../config.dart';

class ImportPdfPageDetectionService {
  Future<Map<String, Map<int, List<int>>>> detect({
    required String section,
    required Map<String, String> pdfPaths,
    required Map<String, int> pageCounts,
    void Function(String message)? onProgress,
  }) async {
    if (AppConfig.geminiApiKey.isEmpty) {
      throw StateError('GEMINI_API_KEY is missing from application config.');
    }
    final parts = section == 'listening' ? [1, 2, 3, 4] : [5, 6, 7];
    final result = <String, Map<int, List<int>>>{};
    for (final lane in ['questions', 'transcripts']) {
      final pdfPath = pdfPaths[lane];
      final pageCount = pageCounts[lane];
      if (pdfPath == null || pageCount == null || pageCount == 0) continue;
      onProgress?.call(
        'Analyzing ${section == 'listening' ? 'Listening' : 'Reading'} $lane PDF pages...',
      );
      final response = await _detectLane(
        lane: lane,
        parts: parts,
        pageCount: pageCount,
        bytes: await File(pdfPath).readAsBytes(),
      );
      result[lane] = response;
    }
    if (result.isEmpty) {
      throw StateError('Select an overall question or transcript PDF first.');
    }
    return result;
  }

  Future<Map<int, List<int>>> _detectLane({
    required String lane,
    required List<int> parts,
    required int pageCount,
    required Uint8List bytes,
  }) async {
    final partList = parts.join(', ');
    final prompt =
        '''Classify every page in the attached selected TOEIC ${lane == 'questions' ? 'question' : 'transcript'} PDF by TOEIC part.
The PDF contains $pageCount pages. Page numbers are 1-based ordinals in this attached PDF, in its current order.
Only assign pages to these parts: $partList. Put a page in the part whose questions or transcript it contains. Assign continuation pages to the same part. Leave cover pages, answer keys, directions, and unrelated material unassigned. Do not omit any relevant page.
Return only JSON in this exact shape, using every listed part as a string key and arrays of page numbers:
{"pages_by_part":{"${parts.first}":[1,2]${parts.skip(1).map((part) => ',"$part":[]').join()}}}''';
    final model = GenerativeModel(
      model: AppConfig.geminiModel,
      apiKey: AppConfig.geminiApiKey,
      generationConfig: GenerationConfig(
        temperature: 0,
        responseMimeType: 'application/json',
      ),
    );
    final response = await model.generateContent([
      Content.multi([TextPart(prompt), DataPart('application/pdf', bytes)]),
    ]);
    final text = response.text;
    if (text == null || text.trim().isEmpty) {
      throw StateError('Gemini returned no page classification for $lane.');
    }
    final cleaned = text
        .replaceAll(RegExp(r'^```(?:json)?\s*|\s*```$', multiLine: true), '')
        .trim();
    final decoded = jsonDecode(cleaned);
    if (decoded is! Map || decoded['pages_by_part'] is! Map) {
      throw const FormatException('Agent response has no pages_by_part map.');
    }
    final mapped = decoded['pages_by_part'] as Map;
    final result = <int, List<int>>{};
    for (final part in parts) {
      final pageNumbers = mapped['$part'];
      if (pageNumbers is! List || pageNumbers.any((page) => page is! int)) {
        throw FormatException(
          'Agent returned invalid page numbers for Part $part.',
        );
      }
      final uniquePages = pageNumbers.cast<int>().toSet().toList()..sort();
      if (uniquePages.any((page) => page < 1 || page > pageCount)) {
        throw FormatException('Agent returned a page outside the $lane PDF.');
      }
      result[part] = uniquePages.map((page) => page - 1).toList();
    }
    return result;
  }
}
