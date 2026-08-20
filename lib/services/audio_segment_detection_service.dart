import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';

import '../config.dart';
import '../models.dart';

class AudioSegmentDetectionService {
  const AudioSegmentDetectionService();

  Future<List<DetectedAudioSegment>> detect({
    required List<SrtChunk> chunks,
    required List<ExamContext> contexts,
  }) async {
    if (AppConfig.geminiApiKey.isEmpty) {
      throw StateError('Set GEMINI_API_KEY at build time to detect audio.');
    }
    if (chunks.isEmpty) throw StateError('No SRT chunks are available.');
    if (contexts.isEmpty) throw StateError('No exam contexts are available.');

    final response = await GenerativeModel(
      model: AppConfig.geminiModel,
      apiKey: AppConfig.geminiApiKey,
      generationConfig: GenerationConfig(
        temperature: 0.1,
        responseMimeType: 'application/json',
      ),
    ).generateContent([Content.text(_buildPrompt(chunks, contexts))]);
    final raw = response.text?.trim();
    if (raw == null || raw.isEmpty) {
      throw StateError('Gemini returned no audio-segment mappings.');
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final mappings = (decoded['mappings'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(
          (value) => AudioSegmentMapping(
            contextId: value['context_id'] as String? ?? '',
            startChunkIndex:
                (value['start_chunk_index'] as num?)?.toInt() ?? -1,
            endChunkIndex: (value['end_chunk_index'] as num?)?.toInt() ?? -1,
          ),
        )
        .toList();
    return _resolve(mappings, chunks, contexts);
  }

  List<DetectedAudioSegment> _resolve(
    List<AudioSegmentMapping> mappings,
    List<SrtChunk> chunks,
    List<ExamContext> contexts,
  ) {
    final chunksByIndex = {for (final chunk in chunks) chunk.index: chunk};
    final contextsById = {for (final context in contexts) context.id: context};
    final results = <DetectedAudioSegment>[];
    for (final mapping in mappings) {
      final start = chunksByIndex[mapping.startChunkIndex];
      final end = chunksByIndex[mapping.endChunkIndex];
      final context = contextsById[mapping.contextId];
      if (context != null &&
          start != null &&
          end != null &&
          end.end > start.start) {
        results.add(
          DetectedAudioSegment(
            context: context,
            start: start.start,
            end: end.end,
          ),
        );
      }
    }
    return results;
  }

  String _buildPrompt(List<SrtChunk> chunks, List<ExamContext> contexts) {
    final srtRows = chunks
        .map(
          (chunk) =>
              '${chunk.index} | ${chunk.start.toStringAsFixed(3)} | ${chunk.end.toStringAsFixed(3)} | ${_oneLine(chunk.text, 500)}',
        )
        .join('\n');
    final contextRows = contexts
        .map((context) {
          final questions = context.questions
              .map((question) {
                final options = question.options
                    .map((item) => _oneLine(item, 180))
                    .join(' | ');
                return '${question.number}: ${_oneLine(question.content, 300)} | $options';
              })
              .join(' ; ');
          final title = _spokenTitle(context);
          return '${context.id} | part ${context.part} | $title | ${_oneLine(context.text, 500)} | questions: $questions';
        })
        .join('\n');
    return '''You align TOEIC exam contexts to an SRT transcript.\n\n[SRT CHUNKS]\n$srtRows\n\n[CONTEXTS]\n$contextRows\n\nFor each listening context (parts 1-4) that occurs in the SRT, return its contiguous inclusive chunk range. For parts 1-2, include the prompt and all spoken answer choices. For parts 3-4, include the spoken preamble (for example, "Questions 50 through 52 refer to..."), the complete conversation/talk, and every following spoken question and choice. Omit reading contexts and any unmatchable context.\n\nReturn JSON only in exactly this shape:\n{"mappings":[{"context_id":"an existing context id","start_chunk_index":1,"end_chunk_index":2}]}''';
  }

  String _spokenTitle(ExamContext context) {
    final numbers =
        context.questions.map((question) => question.number).toList()..sort();
    if ((context.part != 3 && context.part != 4) || numbers.isEmpty) return '';
    final target = context.part == 3 ? 'conversation' : 'talk or announcement';
    return numbers.first == numbers.last
        ? 'Question ${numbers.first} refers to the following $target.'
        : 'Questions ${numbers.first} through ${numbers.last} refer to the following $target.';
  }

  String _oneLine(String value, int limit) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.substring(0, normalized.length.clamp(0, limit));
  }
}
