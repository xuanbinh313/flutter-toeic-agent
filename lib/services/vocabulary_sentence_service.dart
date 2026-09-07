import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';

import '../config.dart';
import '../models.dart';

class VocabularySentenceService {
  const VocabularySentenceService();

  Future<Map<String, ({String sentence, String translation})>> generate(
    Iterable<Vocab> vocabulary,
  ) async {
    if (AppConfig.geminiApiKey.isEmpty) {
      throw StateError(
        'Set GEMINI_API_KEY at build time to generate vocabulary sentences.',
      );
    }
    final entries = vocabulary
        .where((word) => word.word.trim().isNotEmpty)
        .map((word) => {'id': word.id, 'word': word.word})
        .toList();
    if (entries.isEmpty) return {};

    final response =
        await GenerativeModel(
          model: AppConfig.geminiModel,
          apiKey: AppConfig.geminiApiKey,
          generationConfig: GenerationConfig(
            temperature: 0.3,
            responseMimeType: 'application/json',
          ),
        ).generateContent([
          Content.text(
            'You create concise, natural English example sentences for Vietnamese '
            'vocabulary learners. For every supplied item, write one sentence that '
            'uses its exact word or phrase, then translate that complete sentence '
            'into natural Vietnamese. Return only JSON in the form '
            '{"sentences":[{"id":"...","sentence":"...",'
            '"translation":"..."}]}. Include every input exactly once. '
            'Input: ${jsonEncode(entries)}',
          ),
        ]);
    final text = response.text?.trim();
    if (response.candidates.isEmpty || text == null || text.isEmpty) {
      throw StateError('The sentence agent returned no text.');
    }
    final decoded = jsonDecode(_withoutCodeFence(text));
    if (decoded is! Map || decoded['sentences'] is! List) {
      throw const FormatException('Expected a sentences array.');
    }
    final requestedIds = entries.map((entry) => entry['id']).toSet();
    final sentences = <String, ({String sentence, String translation})>{};
    for (final item in decoded['sentences'] as List) {
      if (item is! Map) continue;
      final id = item['id'];
      final sentence = item['sentence'];
      final translation = item['translation'];
      if (id is String &&
          requestedIds.contains(id) &&
          sentence is String &&
          sentence.trim().isNotEmpty &&
          translation is String &&
          translation.trim().isNotEmpty) {
        sentences[id] = (
          sentence: sentence.trim(),
          translation: translation.trim(),
        );
      }
    }
    if (sentences.isEmpty) {
      throw const FormatException('No usable sentences were returned.');
    }
    return sentences;
  }

  String _withoutCodeFence(String value) => value
      .replaceAll(RegExp(r'^```json\s*|\s*```$', multiLine: true), '')
      .trim();
}
