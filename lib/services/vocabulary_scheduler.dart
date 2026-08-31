import 'package:fsrs/fsrs.dart' as fsrs;

import '../models.dart';

class VocabularyScheduler {
  VocabularyScheduler._();

  static final _scheduler = fsrs.Scheduler(enableFuzzing: false);

  static Map<int, Duration> preview(Vocab word) {
    final now = DateTime.now().toUtc();
    return {
      for (final rating in fsrs.Rating.values)
        rating.value: _scheduler
            .reviewCard(_cardFor(word, now), rating, reviewDateTime: now)
            .card
            .due
            .difference(now),
    };
  }

  static void answer(Vocab word, int rating) {
    final now = DateTime.now().toUtc();
    final previousState = word.state;
    final result = _scheduler
        .reviewCard(
          _cardFor(word, now),
          fsrs.Rating.fromValue(rating),
          reviewDateTime: now,
        )
        .card;
    word
      ..dueAt = result.due
      ..stability = result.stability
      ..difficulty = result.difficulty
      ..state = result.state.value
      ..step = result.step
      ..lastReviewedAt = result.lastReview
      ..reps += 1
      ..lastRating = rating;
    if (rating == fsrs.Rating.again.value &&
        previousState == fsrs.State.review.value) {
      word.lapses += 1;
    }
  }

  static List<Vocab> nextCards(Iterable<Vocab> words) {
    final now = DateTime.now();
    final cards = words.where((word) => word.isNew || word.isDue).toList();
    cards.sort((a, b) {
      final aPriority = _priority(a, now);
      final bPriority = _priority(b, now);
      if (aPriority != bPriority) return aPriority.compareTo(bPriority);
      return (a.dueAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
        b.dueAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
    });
    return cards;
  }

  static int _priority(Vocab word, DateTime now) {
    if ((word.state == 1 || word.state == 3) && word.isDue) return 0;
    if (word.state == 2 && word.isDue) return 1;
    return 2;
  }

  static fsrs.Card _cardFor(Vocab word, DateTime now) {
    if (word.state == null ||
        word.stability == null ||
        word.difficulty == null ||
        !const {1, 2, 3}.contains(word.state)) {
      return fsrs.Card(cardId: word.id.hashCode);
    }
    return fsrs.Card(
      cardId: word.id.hashCode,
      state: fsrs.State.fromValue(word.state!),
      step: word.step,
      stability: word.stability,
      difficulty: word.difficulty,
      due: word.dueAt?.toUtc() ?? now,
      lastReview: word.lastReviewedAt?.toUtc() ?? now,
    );
  }
}
