import 'package:flutter/material.dart';

import '../models.dart';
import '../services/vocabulary_scheduler.dart';
import 'vocabulary_review_page.dart';

class VocabularyPage extends StatefulWidget {
  const VocabularyPage({super.key, required this.words, required this.changed});
  final List<Vocab> words;
  final VoidCallback changed;
  @override
  State<VocabularyPage> createState() => _VocabularyPageState();
}

class _VocabularyPageState extends State<VocabularyPage> {
  String _query = '';
  bool _dueOnly = false;
  @override
  Widget build(BuildContext context) {
    final visible = widget.words
        .where(
          (word) =>
              word.word.contains(_query.toLowerCase()) &&
              (!_dueOnly || word.isDue),
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vocabulary',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text('Review words collected from your exam contexts.'),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _startReview,
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  'Start (${VocabularyScheduler.nextCards(widget.words).length})',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search vocabulary...',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilterChip(
                label: const Text('Due only'),
                selected: _dueOnly,
                onSelected: (value) => setState(() => _dueOnly = value),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Expanded(
            child: ListView.separated(
              itemCount: visible.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, index) {
                final word = visible[index];
                return Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              word.word,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: () {
                                setState(() => widget.words.remove(word));
                                widget.changed();
                              },
                              icon: const Icon(Icons.delete_outline),
                              color: Colors.red,
                            ),
                          ],
                        ),
                        Text(word.meaning),
                        const SizedBox(height: 7),
                        Text(
                          word.source,
                          style: const TextStyle(
                            color: Color(0xff52616b),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          children: List.generate(
                            5,
                            (level) => ChoiceChip(
                              label: Text('${level + 1}'),
                              selected: word.status == level + 1,
                              onSelected: (_) => setState(() {
                                word.status = level + 1;
                                widget.changed();
                              }),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startReview() async {
    final cards = VocabularyScheduler.nextCards(widget.words);
    if (cards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No vocabulary is due right now.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VocabularyReviewPage(words: widget.words),
      ),
    );
    if (mounted) {
      setState(() {});
      widget.changed();
    }
  }
}
