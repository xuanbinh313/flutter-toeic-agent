import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/vocabulary_review_store.dart';
import '../services/vocabulary_scheduler.dart';

class VocabularySentenceReviewPage extends StatefulWidget {
  const VocabularySentenceReviewPage({
    super.key,
    required this.words,
    required this.wordIds,
  });

  final List<Vocab> words;
  final Set<String> wordIds;

  @override
  State<VocabularySentenceReviewPage> createState() =>
      _VocabularySentenceReviewPageState();
}

class _VocabularySentenceReviewPageState
    extends State<VocabularySentenceReviewPage> {
  bool _showAnswer = false;
  bool _saving = false;
  int _reviewed = 0;

  Vocab? get _current {
    final cards = VocabularyScheduler.nextCards(widget.words);
    return cards.where((word) => widget.wordIds.contains(word.id)).firstOrNull;
  }

  Future<void> _rate(int rating) async {
    final word = _current;
    if (word == null || _saving || !_showAnswer) return;
    setState(() => _saving = true);
    try {
      VocabularyScheduler.answer(word, rating);
      await VocabularyReviewStore.save(word);
      if (mounted) {
        setState(() {
          _reviewed++;
          _showAnswer = false;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.enter): _showAnswerForCurrent,
      const SingleActivator(LogicalKeyboardKey.numpadEnter):
          _showAnswerForCurrent,
      const SingleActivator(LogicalKeyboardKey.digit1): () => _rate(1),
      const SingleActivator(LogicalKeyboardKey.digit2): () => _rate(2),
      const SingleActivator(LogicalKeyboardKey.digit3): () => _rate(3),
      const SingleActivator(LogicalKeyboardKey.digit4): () => _rate(4),
      const SingleActivator(LogicalKeyboardKey.numpad1): () => _rate(1),
      const SingleActivator(LogicalKeyboardKey.numpad2): () => _rate(2),
      const SingleActivator(LogicalKeyboardKey.numpad3): () => _rate(3),
      const SingleActivator(LogicalKeyboardKey.numpad4): () => _rate(4),
    },
    child: Focus(autofocus: true, child: _scaffold(context)),
  );

  void _showAnswerForCurrent() {
    if (_current != null && !_showAnswer && !_saving) {
      setState(() => _showAnswer = true);
    }
  }

  Widget _scaffold(BuildContext context) {
    final word = _current;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sentence review'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Center(child: Text('Reviewed: $_reviewed')),
          ),
        ],
      ),
      body: word == null ? _complete() : _review(word),
    );
  }

  Widget _complete() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.celebration_outlined, size: 52),
        const SizedBox(height: 16),
        const Text('All caught up!', style: TextStyle(fontSize: 24)),
        const SizedBox(height: 8),
        Text('You reviewed $_reviewed word${_reviewed == 1 ? '' : 's'}.'),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to vocabulary'),
        ),
      ],
    ),
  );

  Widget _review(Vocab word) {
    final previews = VocabularyScheduler.preview(word);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Card(
                  elevation: 0,
                  child: SelectionArea(
                    child: Padding(
                      padding: const EdgeInsets.all(36),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SelectableText.rich(
                              _sentenceText(word),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 30),
                            ),
                            const SizedBox(height: 18),
                            if (_showAnswer) ...[
                              const Divider(),
                              const SizedBox(height: 18),
                              SelectableText(
                                word.sentenceTranslation,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ] else
                              const Text('Press Enter or use Show answer.'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_showAnswer)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                _ratingButton('Again', 1, previews[1]!, Colors.red),
                _ratingButton('Hard', 2, previews[2]!, Colors.orange),
                _ratingButton('Good', 3, previews[3]!, Colors.blue),
                _ratingButton('Easy', 4, previews[4]!, Colors.green),
              ],
            )
          else
            FilledButton(
              onPressed: _showAnswerForCurrent,
              child: const Text('Show answer'),
            ),
        ],
      ),
    );
  }

  TextSpan _sentenceText(Vocab word) {
    final sentence = word.sentence;
    final target = word.word.trim();
    if (target.isEmpty) return TextSpan(text: sentence);
    final matches = RegExp(
      RegExp.escape(target),
      caseSensitive: false,
    ).allMatches(sentence);
    if (matches.isEmpty) return TextSpan(text: sentence);
    final spans = <TextSpan>[];
    var start = 0;
    for (final match in matches) {
      if (match.start > start) {
        spans.add(TextSpan(text: sentence.substring(start, match.start)));
      }
      spans.add(
        TextSpan(
          text: sentence.substring(match.start, match.end),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      );
      start = match.end;
    }
    if (start < sentence.length) {
      spans.add(TextSpan(text: sentence.substring(start)));
    }
    return TextSpan(children: spans);
  }

  Widget _ratingButton(
    String label,
    int rating,
    Duration interval,
    Color color,
  ) => FilledButton(
    style: FilledButton.styleFrom(backgroundColor: color),
    onPressed: _saving ? null : () => _rate(rating),
    child: Text('$label (${_formatInterval(interval)})'),
  );

  String _formatInterval(Duration value) {
    if (value.inMinutes < 60) return '${value.inMinutes}m';
    if (value.inHours < 24) return '${value.inHours}h';
    return '${value.inDays}d';
  }
}
