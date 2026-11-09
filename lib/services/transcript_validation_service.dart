import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';

import '../config.dart';
import '../models.dart';

class TranscriptValidationResult {
  const TranscriptValidationResult(this.chunks, this.repairCount);

  final List<SrtChunk> chunks;
  final int repairCount;
}

class TranscriptValidationService {
  const TranscriptValidationService();

  Future<TranscriptValidationResult> validate({
    required List<SrtChunk> chunks,
    required List<ExamContext> contexts,
  }) async {
    if (AppConfig.geminiApiKey.isEmpty) {
      throw StateError('Set GEMINI_API_KEY to validate the transcript.');
    }
    if (chunks.isEmpty || contexts.isEmpty) {
      throw StateError('Transcript chunks and exam contexts are required.');
    }
    final response = await GenerativeModel(
      model: AppConfig.geminiModel,
      apiKey: AppConfig.geminiApiKey,
      generationConfig: GenerationConfig(
        temperature: 0.1,
        responseMimeType: 'application/json',
      ),
    ).generateContent([Content.text(_prompt(chunks, contexts))]);
    final raw = response.text?.trim();
    if (raw == null || raw.isEmpty) {
      throw StateError('The transcript agent returned no validation result.');
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final applied = _applyRepairs(
      chunks,
      decoded['repairs'] as List? ?? const [],
    );
    final corrected = _correctRepeatedOptionLabels(applied.chunks, contexts);
    final labels = _correctMisheardChoiceLabels(corrected.chunks, contexts);
    return TranscriptValidationResult(
      labels.chunks,
      applied.count + corrected.count + labels.count,
    );
  }

  ({List<SrtChunk> chunks, int count}) _applyRepairs(
    List<SrtChunk> chunks,
    List<dynamic> raw,
  ) {
    final repairs = <int, List<Map<String, dynamic>>>{};
    for (final item in raw.whereType<Map>()) {
      final index = (item['chunk_index'] as num?)?.toInt();
      final pieces = (item['pieces'] as List?)
          ?.whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();
      if (index != null && pieces != null && pieces.isNotEmpty) {
        repairs[index] = pieces;
      }
    }
    final output = <SrtChunk>[];
    var repairedCount = 0;
    for (final chunk in chunks) {
      final pieces = repairs.remove(chunk.index);
      if (pieces == null || !_validPieces(chunk, pieces)) {
        output.add(chunk);
        continue;
      }
      if (pieces.length == 1 &&
          (pieces.first['text'] as String).trim() == chunk.text.trim()) {
        output.add(chunk);
        continue;
      }
      repairedCount++;
      for (var i = 0; i < pieces.length; i++) {
        final piece = pieces[i];
        output.add(
          SrtChunk(
            id: i == 0
                ? chunk.id
                : '${DateTime.now().microsecondsSinceEpoch}-${chunk.id}-$i',
            index: output.length,
            start: i == 0 ? chunk.start : (piece['start'] as num).toDouble(),
            end: i == pieces.length - 1
                ? chunk.end
                : (piece['end'] as num).toDouble(),
            text: (piece['text'] as String).trim(),
            hint: chunk.hint,
            words: _matchWords(chunk.words, (piece['text'] as String)),
          ),
        );
      }
    }
    return (chunks: output, count: repairedCount);
  }

  bool _validPieces(SrtChunk chunk, List<Map<String, dynamic>> pieces) {
    final firstStart = (pieces.first['start'] as num?)?.toDouble();
    final lastEnd = (pieces.last['end'] as num?)?.toDouble();
    if (firstStart == null ||
        lastEnd == null ||
        firstStart - chunk.start > 0.5 ||
        chunk.end - lastEnd > 0.5) {
      return false;
    }
    var previousEnd = chunk.start;
    for (final piece in pieces) {
      final start = (piece['start'] as num?)?.toDouble();
      final end = (piece['end'] as num?)?.toDouble();
      final text = piece['text'];
      if (start == null ||
          end == null ||
          text is! String ||
          text.trim().isEmpty ||
          start < previousEnd ||
          end <= start ||
          start < chunk.start ||
          end > chunk.end) {
        return false;
      }
      previousEnd = end;
    }
    return true;
  }

  String _prompt(List<SrtChunk> chunks, List<ExamContext> contexts) {
    final transcriptRows = chunks
        .map(
          (chunk) => <String, Object?>{
            'chunk_index': chunk.index,
            'start': chunk.start,
            'end': chunk.end,
            'text': chunk.text,
            if (chunk.words.isNotEmpty) 'words': chunk.words,
          },
        )
        .toList();
    final contextRows = contexts
        .where((context) => context.part <= 4)
        .map(
          (context) => <String, Object?>{
            'context_id': context.id,
            'part': context.part,
            'transcript': context.text,
            'questions': context.questions
                .map(
                  (question) => {
                    'number': question.number,
                    'content': question.content,
                    'options': question.options,
                  },
                )
                .toList(),
          },
        )
        .toList();
    return '''Validate each TOEIC listening chunk against its context transcript and question/answer choices. Check both wrong transcript content and incorrect chunk boundaries. A spoken answer label "C" may be recognized as the word "See"; verify short isolated chunks against the neighboring B and C answer choices.
Correct obvious recognition corruption when the context gives a clear exact spoken phrase. For Parts 1-2, use the context's answer choices as the reference: remove duplicated or hallucinated letter tokens (for example "A A B B") when the remaining words clearly match one option, and retain the correct spoken choice label if its source word timing exists. For Parts 3-4, compare against the context transcript and its question group. Do not invent speech, and do not change correct text.
If one chunk contains multiple separately timed sentences/options/groups, split it into ordered pieces. For a text correction with no split, return exactly one piece covering the original chunk. Each piece's start/end must be inside the original chunk, ordered, and together preserve its full time coverage. Do not rewrite ordinary differences unless the context makes the correct phrase clear.
Return only changed chunks. When splitting, use the existing word timestamps to choose boundaries. Return JSON only: {"repairs":[{"chunk_index":1,"reason":"brief reason","pieces":[{"start":0.0,"end":1.0,"text":"corrected words"}]}]}. Return an empty repairs array only if every transcript is accurate and correctly split.

[CONTEXTS AND QUESTIONS]
${jsonEncode(contextRows)}

[TRANSCRIPT CHUNKS]
${jsonEncode(transcriptRows)}''';
  }

  List<Map<String, dynamic>> _matchWords(
    List<Map<String, dynamic>> source,
    String text,
  ) {
    final target = _tokens(text);
    if (source.isEmpty || target.isEmpty) return const [];
    final sourceTokens = source
        .map((word) => _tokens('${word['word']}'))
        .toList();
    List<int>? bestMatch;
    for (var start = 0; start < source.length; start++) {
      if (!sourceTokens[start].contains(target.first)) continue;
      final positions = <int>[start];
      var next = start + 1;
      for (final token in target.skip(1)) {
        while (next < source.length && !sourceTokens[next].contains(token)) {
          next++;
        }
        if (next == source.length) break;
        positions.add(next++);
      }
      if (positions.length == target.length &&
          (bestMatch == null ||
              positions.last - positions.first <
                  bestMatch.last - bestMatch.first)) {
        bestMatch = positions;
      }
    }
    return bestMatch == null
        ? const []
        : bestMatch.map((index) => source[index]).toList();
  }

  List<String> _tokens(String value) => RegExp(
    r"[A-Za-z0-9]+(?:['’][A-Za-z0-9]+)*",
  ).allMatches(value.toLowerCase()).map((match) => match.group(0)!).toList();

  ({List<SrtChunk> chunks, int count}) _correctRepeatedOptionLabels(
    List<SrtChunk> chunks,
    List<ExamContext> contexts,
  ) {
    final output = <SrtChunk>[];
    var count = 0;
    for (final chunk in chunks) {
      final hasRepeatedLabel = RegExp(
        r'\b([A-D])(?:\s+\1)+\b',
        caseSensitive: false,
      ).hasMatch(chunk.text);
      final correction = hasRepeatedLabel
          ? _optionCorrection(chunk, contexts)
          : null;
      if (correction == null) {
        output.add(chunk);
      } else {
        output.add(correction);
        count++;
      }
    }
    return (chunks: output, count: count);
  }

  ({List<SrtChunk> chunks, int count}) _correctMisheardChoiceLabels(
    List<SrtChunk> chunks,
    List<ExamContext> contexts,
  ) {
    final output = [...chunks];
    var count = 0;
    for (var i = 1; i < output.length - 1; i++) {
      final chunk = output[i];
      if (_normalize(chunk.text) != 'see' || chunk.end - chunk.start > 1.5) {
        continue;
      }
      final previous = _normalize(output[i - 1].text);
      final cAnswers = _followingAnswers(output, i + 1);
      final belongsToContext = contexts
          .where((context) => context.part == 2)
          .expand((context) => context.questions)
          .any((question) {
            if (question.options.length < 3) return false;
            return previous == _normalize(question.options[1]) &&
                cAnswers.contains(_normalize(question.options[2]));
          });
      if (!belongsToContext) continue;
      output[i] = SrtChunk(
        id: chunk.id,
        index: chunk.index,
        start: chunk.start,
        end: chunk.end,
        text: 'C.',
        hint: chunk.hint,
        words: [
          for (final word in chunk.words) {...word, 'word': ' C'},
        ],
      );
      count++;
    }
    return (chunks: output, count: count);
  }

  List<String> _followingAnswers(List<SrtChunk> chunks, int start) => [
    for (var count = 1; count <= 4 && start + count <= chunks.length; count++)
      _normalize(
        chunks.skip(start).take(count).map((chunk) => chunk.text).join(' '),
      ),
  ];

  String _normalize(String value) => _tokens(value).join(' ');

  SrtChunk? _optionCorrection(SrtChunk chunk, List<ExamContext> contexts) {
    if (chunk.words.isEmpty) return null;
    final source = <({int wordIndex, String token})>[];
    for (var i = 0; i < chunk.words.length; i++) {
      for (final token in _tokens('${chunk.words[i]['word']}')) {
        source.add((wordIndex: i, token: token));
      }
    }
    for (final context in contexts.where((item) => item.part <= 2)) {
      for (final question in context.questions) {
        for (
          var optionIndex = 0;
          optionIndex < question.options.length && optionIndex < 4;
          optionIndex++
        ) {
          final optionTokens = _tokens(question.options[optionIndex]);
          final start = _findSequence(source, optionTokens);
          if (start < 0) continue;
          final letter = String.fromCharCode(65 + optionIndex).toLowerCase();
          var labelPosition = -1;
          for (var i = start - 1; i >= 0 && i >= start - 5; i--) {
            if (source[i].token == letter) {
              labelPosition = i;
              break;
            }
          }
          final labelWord = labelPosition < 0
              ? null
              : source[labelPosition].wordIndex;
          final wordIndexes = <int>{
            ?labelWord,
            for (var i = start; i < start + optionTokens.length; i++)
              source[i].wordIndex,
          };
          return SrtChunk(
            id: chunk.id,
            index: chunk.index,
            start: chunk.start,
            end: chunk.end,
            text: '${letter.toUpperCase()}. ${question.options[optionIndex]}',
            hint: chunk.hint,
            words: [for (final i in wordIndexes) chunk.words[i]],
          );
        }
      }
    }
    return null;
  }

  int _findSequence(
    List<({int wordIndex, String token})> source,
    List<String> target,
  ) {
    if (target.isEmpty) return -1;
    for (var start = 0; start <= source.length - target.length; start++) {
      var matches = true;
      for (var i = 0; i < target.length; i++) {
        if (source[start + i].token != target[i]) {
          matches = false;
          break;
        }
      }
      if (matches) return start;
    }
    return -1;
  }
}
