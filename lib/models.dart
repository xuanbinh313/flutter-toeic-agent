class Exam {
  Exam({
    required this.title,
    required this.description,
    required this.duration,
    required this.questions,
    this.published = false,
    this.id = '',
    this.createdAt = '',
    this.audioName,
    this.audioPath,
  });

  String title;
  String description;
  int duration;
  final int questions;
  String id;
  final String? createdAt;
  String? audioName;
  String? audioPath;
  bool published;
}

class Vocab {
  Vocab(
    this.word,
    this.meaning,
    this.source, [
    this.status = 1,
    this.id = '',
    this.dueAt,
    this.stability,
    this.difficulty,
    this.reps = 0,
    this.lapses = 0,
    this.state,
    this.step,
    this.lastReviewedAt,
    this.lastRating,
    this.sentence = '',
    this.sentenceTranslation = '',
  ]);

  String word;
  String meaning;
  String source;
  int status;
  final String id;
  DateTime? dueAt;
  double? stability;
  double? difficulty;
  int reps;
  int lapses;
  int? state;
  int? step;
  DateTime? lastReviewedAt;
  int? lastRating;
  String sentence;
  String sentenceTranslation;

  bool get isNew => state == null;
  bool get isDue => isNew || dueAt == null || !dueAt!.isAfter(DateTime.now());
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
    required this.mode,
  });

  final String id;
  final String createdAt;
  final int durationSeconds;
  final int totalCorrect;
  final int totalQuestions;
  final List<int> selectedParts;
  final List<String> questionTags;
  final String mode;
  double get accuracy =>
      totalQuestions == 0 ? 0 : totalCorrect * 100 / totalQuestions;
}

class AttemptAnswerDetail {
  const AttemptAnswerDetail({
    required this.questionId,
    required this.contextId,
    required this.questionNumber,
    required this.part,
    required this.category,
    required this.content,
    required this.contextText,
    required this.contextNote,
    required this.questionNote,
    required this.tags,
    required this.options,
    required this.userChoice,
    required this.correctAnswer,
    required this.isCorrect,
  });

  final String questionId;
  final String contextId;
  final int questionNumber;
  final int part;
  final String category;
  final String content;
  final String contextText;
  final String contextNote;
  final String questionNote;
  final List<String> tags;
  final List<String> options;
  final String? userChoice;
  final String correctAnswer;
  final bool isCorrect;

  bool get isSkipped => userChoice == null;
  String optionText(String? letter) {
    final index = letter == null || letter.isEmpty
        ? -1
        : letter.codeUnitAt(0) - 65;
    return index >= 0 && index < options.length ? options[index] : '';
  }
}

class AttemptCategoryBreakdown {
  const AttemptCategoryBreakdown(this.name, this.answers);

  final String name;
  final List<AttemptAnswerDetail> answers;
  int get correct => answers.where((answer) => answer.isCorrect).length;
  int get skipped => answers.where((answer) => answer.isSkipped).length;
  int get wrong => answers.length - correct - skipped;
  double get accuracy => answers.isEmpty ? 0 : correct * 100 / answers.length;
}
