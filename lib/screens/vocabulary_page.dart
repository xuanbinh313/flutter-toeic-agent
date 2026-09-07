import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../models.dart';
import '../features/vocabulary/vocabulary_edit_dialog.dart';
import '../services/vocabulary_scheduler.dart';
import '../services/vocabulary_review_store.dart';
import '../services/vocabulary_sentence_cache.dart';
import '../services/vocabulary_sentence_service.dart';
import '../services/vocabulary_translation_service.dart';
import 'vocabulary_review_page.dart';
import 'vocabulary_sentence_review_page.dart';

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
  bool _isTranslating = false;
  bool _isGeneratingSentences = false;
  @override
  Widget build(BuildContext context) {
    final visible = widget.words
        .where(
          (word) =>
              word.word.toLowerCase().contains(_query.toLowerCase()) &&
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
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _isGeneratingSentences ? null : _startSentenceReview,
                icon: _isGeneratingSentences
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.format_quote),
                label: Text(
                  _isGeneratingSentences
                      ? 'Creating sentences...'
                      : 'Start by sentence',
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _isTranslating ? null : _translateEmptyMeanings,
                icon: _isTranslating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(
                  _isTranslating ? 'Translating...' : 'AI Translate Empty',
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
                              tooltip: 'Edit word',
                              onPressed: () => _editWord(word),
                              icon: const Icon(Icons.edit_outlined),
                            ),
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

  Future<void> _editWord(Vocab word) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => VocabularyEditDialog(word: word),
    );
    if (saved == true && mounted) {
      setState(() {});
      widget.changed();
    }
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

  Future<void> _translateEmptyMeanings() async {
    final targets = widget.words
        .where((word) => word.meaning.trim().isEmpty)
        .toList();
    if (targets.isEmpty) {
      _showMessage('All vocabulary entries already have meanings.');
      return;
    }
    setState(() => _isTranslating = true);
    try {
      final translations = await const VocabularyTranslationService().translate(
        targets,
      );
      await VocabularyReviewStore.saveMeanings(translations);
      for (final word in targets) {
        final meaning = translations[word.id];
        if (meaning != null) word.meaning = meaning;
      }
      if (!mounted) return;
      setState(() {});
      widget.changed();
      _showMessage(
        translations.isEmpty
            ? 'No vocabulary translations were returned.'
            : 'Updated ${translations.length} vocabulary meaning(s).',
      );
    } on GenerativeAIException catch (error) {
      _showMessage('Translation agent failed: ${error.message}');
    } on FormatException catch (error) {
      _showMessage('Translation agent returned invalid JSON: ${error.message}');
    } catch (error) {
      _showMessage('Could not translate vocabulary: $error');
    } finally {
      if (mounted) setState(() => _isTranslating = false);
    }
  }

  Future<void> _startSentenceReview() async {
    final cards = VocabularyScheduler.nextCards(widget.words);
    if (cards.isEmpty) {
      _showMessage('No vocabulary is due right now.');
      return;
    }

    setState(() => _isGeneratingSentences = true);
    try {
      if (!await VocabularySentenceCache.wasGeneratedToday()) {
        final sentences = await const VocabularySentenceService().generate(
          cards,
        );
        await VocabularyReviewStore.saveSentences(sentences);
        for (final word in cards) {
          final generated = sentences[word.id];
          if (generated != null) {
            word.sentence = generated.sentence;
            word.sentenceTranslation = generated.translation;
          }
        }
        await VocabularySentenceCache.markGeneratedToday();
      }
      final reviewCards = cards
          .where(
            (word) =>
                word.sentence.trim().isNotEmpty &&
                word.sentenceTranslation.trim().isNotEmpty,
          )
          .toList();
      if (reviewCards.isEmpty) {
        _showMessage('No saved sentences are available for today’s due words.');
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VocabularySentenceReviewPage(
            words: widget.words,
            wordIds: reviewCards.map((word) => word.id).toSet(),
          ),
        ),
      );
      if (mounted) {
        setState(() {});
        widget.changed();
      }
    } on GenerativeAIException catch (error) {
      _showMessage('Sentence agent failed: ${error.message}');
    } on FormatException catch (error) {
      _showMessage('Sentence agent returned invalid JSON: ${error.message}');
    } catch (error) {
      _showMessage('Could not create vocabulary sentences: $error');
    } finally {
      if (mounted) setState(() => _isGeneratingSentences = false);
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
