import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';

import '../config.dart';
import '../models.dart';

class TranscriptTranslationService {
  const TranscriptTranslationService();

  Future<int> translate(List<SrtChunk> chunks) async {
    if (AppConfig.geminiApiKey.isEmpty) {
      throw StateError(
        'Set GEMINI_API_KEY at build time to translate transcripts.',
      );
    }
    final entries = chunks
        .where((chunk) => chunk.text.trim().isNotEmpty)
        .map((chunk) => {'id': chunk.id, 'text': chunk.text})
        .toList();
    if (entries.isEmpty) {
      throw StateError('No transcript text is available to translate.');
    }
    final response =
        await GenerativeModel(
          model: AppConfig.geminiModel,
          apiKey: AppConfig.geminiApiKey,
          generationConfig: GenerationConfig(
            temperature: 0,
            responseMimeType: 'application/json',
          ),
        ).generateContent([
          Content.text(
            'Translate every English transcript to natural Vietnamese. Return a JSON object only, mapping each supplied id to its translation. Input: ${jsonEncode(entries)}',
          ),
        ]);
    if (response.candidates.isEmpty ||
        response.text == null ||
        response.text!.isEmpty) {
      throw StateError('The translation agent returned no text.');
    }
    final translations =
        jsonDecode(
              response.text!
                  .replaceAll(
                    RegExp(r'^```json\s*|\s*```$', multiLine: true),
                    '',
                  )
                  .trim(),
            )
            as Map<String, dynamic>;
    var translatedCount = 0;
    for (final chunk in chunks) {
      final translation = translations[chunk.id];
      if (translation is String && translation.trim().isNotEmpty) {
        chunk.hint = translation.trim();
        translatedCount++;
      }
    }
    return translatedCount;
  }
}
