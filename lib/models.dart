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
  String id;
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

class AudioSegmentMapping {
  const AudioSegmentMapping({
    required this.contextId,
    required this.startChunkIndex,
    required this.endChunkIndex,
  });

  final String contextId;
  final int startChunkIndex;
  final int endChunkIndex;
}

class DetectedAudioSegment {
  const DetectedAudioSegment({
    required this.context,
    required this.start,
    required this.end,
  });

  final ExamContext context;
  final double start;
  final double end;
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
    this.imagePath,
    this.imageFilename,
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
  final String? imagePath;
  final String? imageFilename;
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

class AttemptSummary {
  AttemptSummary({
    required this.id,
    required this.createdAt,
    required this.durationSeconds,
    required this.totalCorrect,
    required this.totalQuestions,
    required this.selectedParts,
    required this.questionTags,
  });

  final String id;
  final String createdAt;
  final int durationSeconds;
  final int totalCorrect;
  final int totalQuestions;
  final List<int> selectedParts;
  final List<String> questionTags;
  double get accuracy =>
      totalQuestions == 0 ? 0 : totalCorrect * 100 / totalQuestions;
}
