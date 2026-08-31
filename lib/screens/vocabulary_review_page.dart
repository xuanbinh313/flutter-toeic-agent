import 'package:flutter/material.dart';

import '../models.dart';
import '../services/vocabulary_scheduler.dart';
import '../services/vocabulary_review_store.dart';

class VocabularyReviewPage extends StatefulWidget {
  const VocabularyReviewPage({super.key, required this.words});

  final List<Vocab> words;

  @override
  State<VocabularyReviewPage> createState() => _VocabularyReviewPageState();
}

class _VocabularyReviewPageState extends State<VocabularyReviewPage> {
  bool _showAnswer = false;
  bool _saving = false;
  int _reviewed = 0;

  Vocab? get _current {
    final cards = VocabularyScheduler.nextCards(widget.words);
    return cards.isEmpty ? null : cards.first;
  }

  Future<void> _rate(int rating) async {
    final word = _current;
    if (word == null || _saving) return;
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
  Widget build(BuildContext context) {
    final word = _current;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vocabulary review'),
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
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _showAnswer
                        ? null
                        : () => setState(() => _showAnswer = true),
                    child: Padding(
                      padding: const EdgeInsets.all(36),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              word.word,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 18),
                            if (_showAnswer) ...[
                              const Divider(),
                              const SizedBox(height: 18),
                              Text(
                                word.meaning.isEmpty
                                    ? 'No Vietnamese translation saved.'
                                    : word.meaning,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 24),
                              ),
                              if (word.source.isNotEmpty) ...[
                                const SizedBox(height: 22),
                                Text(
                                  word.source,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xff52616b),
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ] else
                              const Text('Tap to show Vietnamese translation'),
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
              onPressed: () => setState(() => _showAnswer = true),
              child: const Text('Show answer'),
            ),
        ],
      ),
    );
  }

  Widget _ratingButton(
    String label,
    int rating,
    Duration interval,
    Color color,
  ) {
    return FilledButton(
      style: FilledButton.styleFrom(backgroundColor: color),
      onPressed: _saving ? null : () => _rate(rating),
      child: Text('$label (${_formatInterval(interval)})'),
    );
  }

  String _formatInterval(Duration value) {
    if (value.inMinutes < 60) return '${value.inMinutes}m';
    if (value.inHours < 24) return '${value.inHours}h';
    return '${value.inDays}d';
  }
}
