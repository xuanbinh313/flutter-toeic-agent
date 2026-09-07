import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';

import '../config.dart';
import '../models.dart';

class VocabularyTranslationService {
  const VocabularyTranslationService();

  Future<Map<String, String>> translate(Iterable<Vocab> vocabulary) async {
    if (AppConfig.geminiApiKey.isEmpty) {
      throw StateError(
        'Set GEMINI_API_KEY at build time to translate vocabulary.',
      );
    }
    final entries = vocabulary
        .where((word) => word.word.trim().isNotEmpty)
        .map(
          (word) => {
            'id': word.id,
            'word': word.word,
            'source_context': word.source,
          },
        )
        .toList();
    if (entries.isEmpty) return {};

    final response =
        await GenerativeModel(
          model: AppConfig.geminiModel,
          apiKey: AppConfig.geminiApiKey,
          generationConfig: GenerationConfig(
            temperature: 0.1,
            responseMimeType: 'application/json',
          ),
        ).generateContent([
          Content.text(
            'You are a vocabulary translation assistant for English learners. '
            'Translate each English word or phrase into natural Vietnamese. '
            'Use source_context only to resolve ambiguity. Return only a JSON '
            'object with a translations array; each item must have the supplied '
            'id and a non-empty meaning. Input: ${jsonEncode(entries)}',
          ),
        ]);
    final text = response.text?.trim();
    if (response.candidates.isEmpty || text == null || text.isEmpty) {
      throw StateError('The translation agent returned no text.');
    }
    final decoded = jsonDecode(_withoutCodeFence(text));
    if (decoded is! Map || decoded['translations'] is! List) {
      throw const FormatException('Expected a translations array.');
    }
    final requestedIds = entries.map((entry) => entry['id']).toSet();
    final translations = <String, String>{};
    for (final item in decoded['translations'] as List) {
      if (item is! Map) continue;
      final id = item['id'];
      final meaning = item['meaning'];
      if (id is String &&
          requestedIds.contains(id) &&
          meaning is String &&
          meaning.trim().isNotEmpty) {
        translations[id] = meaning.trim();
      }
    }
    return translations;
  }

  String _withoutCodeFence(String value) => value
      .replaceAll(RegExp(r'^```json\s*|\s*```$', multiLine: true), '')
      .trim();
}
