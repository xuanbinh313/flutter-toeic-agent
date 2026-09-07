import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/vocabulary_review_store.dart';

class VocabularyEditDialog extends StatefulWidget {
  const VocabularyEditDialog({super.key, required this.word});

  final Vocab word;

  @override
  State<VocabularyEditDialog> createState() => _VocabularyEditDialogState();
}

class _VocabularyEditDialogState extends State<VocabularyEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _word = TextEditingController(text: widget.word.word);
  late final _meaning = TextEditingController(text: widget.word.meaning);
  late final _source = TextEditingController(text: widget.word.source);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _word.dispose();
    _meaning.dispose();
    _source.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final word = _word.text.trim();
    final meaning = _meaning.text.trim();
    final source = _source.text.trim();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await VocabularyReviewStore.saveDetails(
        id: widget.word.id,
        word: word,
        meaning: meaning,
        source: source,
      );
      widget.word
        ..word = word
        ..meaning = meaning
        ..source = source;
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save changes. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('Edit word'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _word,
                    autofocus: true,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: 'Word'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter a word.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _meaning,
                    enabled: !_saving,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Meaning'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _source,
                    enabled: !_saving,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: 'Source text'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving...' : 'Save'),
          ),
        ],
      ),
    );
  }
}
