import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';

import '../config.dart';
import '../models.dart';

typedef VocabularySentenceQuestion = ({
  String prompt,
  List<String> options,
  String answer,
});

class VocabularySentenceQuestionService {
  const VocabularySentenceQuestionService();

  Future<Map<String, VocabularySentenceQuestion>> generate(
    Iterable<Vocab> vocabulary,
  ) async {
    if (AppConfig.geminiApiKey.isEmpty) {
      throw StateError(
        'Set GEMINI_API_KEY at build time to create practice questions.',
      );
    }
    final entries = vocabulary
        .where(
          (word) =>
              word.word.trim().isNotEmpty && word.sentence.trim().isNotEmpty,
        )
        .map(
          (word) => {
            'id': word.id,
            'word': word.word,
            'sentence': word.sentence,
            'meaning': word.meaning,
          },
        )
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
            'Create one English vocabulary multiple-choice fill-in-the-blank question '
            'for every input. Replace the target vocabulary word or phrase in its '
            'sentence with exactly one blank represented as "_____". Provide exactly '
            'four distinct options, including the exact target word or phrase as the '
            'correct answer. The answer must exactly match one option. Distractors '
            'must be plausible English vocabulary. Return only JSON: '
            '{"questions":[{"id":"...","prompt":"...","options":["...", '
            '"...","...","..."],"answer":"..."}]}. Include every id once. '
            'Input: ${jsonEncode(entries)}',
          ),
        ]);
    final text = response.text?.trim();
    if (response.candidates.isEmpty || text == null || text.isEmpty) {
      throw StateError('The question agent returned no text.');
    }
    final decoded = jsonDecode(_withoutCodeFence(text));
    if (decoded is! Map || decoded['questions'] is! List) {
      throw const FormatException('Expected a questions array.');
    }
    final wordsById = {
      for (final entry in entries)
        entry['id'] as String: entry['word'] as String,
    };
    final questions = <String, VocabularySentenceQuestion>{};
    for (final item in decoded['questions'] as List) {
      if (item is! Map) continue;
      final id = item['id'];
      final prompt = item['prompt'];
      final rawOptions = item['options'];
      final answer = item['answer'];
      if (id is! String ||
          !wordsById.containsKey(id) ||
          prompt is! String ||
          rawOptions is! List ||
          answer is! String)
        continue;
      final options = rawOptions
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      if (!prompt.contains('_____') ||
          options.length != 4 ||
          options.toSet().length != 4 ||
          answer.trim() != wordsById[id] ||
          !options.contains(answer.trim()))
        continue;
      questions[id] = (
        prompt: prompt.trim(),
        options: options,
        answer: answer.trim(),
      );
    }
    if (questions.isEmpty) {
      throw const FormatException(
        'No usable vocabulary questions were returned.',
      );
    }
    return questions;
  }

  String _withoutCodeFence(String value) => value
      .replaceAll(RegExp(r'^```json\s*|\s*```$', multiLine: true), '')
      .trim();
}
