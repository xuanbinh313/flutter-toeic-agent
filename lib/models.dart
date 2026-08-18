class Exam {
  Exam({
    required this.title,
    required this.description,
    required this.duration,
    required this.questions,
    this.published = false,
    this.id = '',
    this.audioName,
    this.audioPath,
  });

  String title;
  String description;
  int duration;
  final int questions;
  final String id;
  String? audioName;
  String? audioPath;
  bool published;
}

class Vocab {
  Vocab(this.word, this.meaning, this.source, [this.status = 1, this.id = '']);

  final String word;
  final String meaning;
  final String source;
  int status;
  final String id;
}

class SrtChunk {
  SrtChunk({
    required this.id,
    required this.index,
    required this.start,
    required this.end,
    required this.text,
    this.hint,
  });
  final String id;
  int index;
  double start;
  double end;
  String text;
  String? hint;
}

class ExamContext {
  ExamContext({
    required this.id,
    required this.part,
    required this.type,
    required this.index,
    required this.text,
    required this.note,
    required this.audioStart,
    required this.audioEnd,
    required this.questions,
  });

  final String id;
  final int part;
  final String type;
  final int index;
  final String text;
  final String note;
  final double audioStart;
  final double audioEnd;
  final List<ExamQuestion> questions;
}

class ExamQuestion {
  ExamQuestion({
    required this.id,
    required this.number,
    required this.type,
    required this.content,
    required this.options,
    required this.correctAnswer,
    required this.note,
  });

  final String id;
  final int number;
  final String type;
  final String content;
  final List<String> options;
  final String correctAnswer;
  final String note;
}
