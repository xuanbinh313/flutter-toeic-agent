import 'dart:convert';

import 'package:path/path.dart' as path;

class PartOneAgentResponse {
  const PartOneAgentResponse._();

  static Object decode(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'^```(?:json)?\s*|\s*```$', multiLine: true), '')
        .trim();
    return jsonDecode(cleaned);
  }

  static List<Map<String, dynamic>> imageRegions(Object decoded) {
    if (decoded is! Map || decoded['image_regions'] is! List) {
      throw const FormatException(
        'Part 1 response has no image_regions array.',
      );
    }
    return (decoded['image_regions'] as List).map((row) {
      if (row is! Map ||
          row['question_number'] is! int ||
          row['page'] is! int) {
        throw const FormatException(
          'Part 1 response contains an invalid image region.',
        );
      }
      return Map<String, dynamic>.from(row);
    }).toList();
  }

  static List<Map<String, dynamic>> contexts(Object decoded, int selectedPart) {
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

  static void applyImages(
    List<Map<String, dynamic>> contexts,
    List<String> imagePaths,
  ) {
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
      if (index >= contexts.length) contexts.add(context);
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
}
