import 'package:flutter/material.dart';

import '../services/local_database.dart';

/// Selectable text that can be saved as a vocabulary item for an exam context.
class VocabularySelectableText extends StatefulWidget {
  const VocabularySelectableText({
    super.key,
    required this.text,
    required this.contextId,
    required this.sourceText,
    this.style,
    this.onVocabularyAdded,
  });

  final String text;
  final String contextId;
  final String sourceText;
  final TextStyle? style;
  final VoidCallback? onVocabularyAdded;

  @override
  State<VocabularySelectableText> createState() =>
      _VocabularySelectableTextState();
}

class _VocabularySelectableTextState extends State<VocabularySelectableText> {
  bool _saving = false;

  String _selectedText(TextSelection selection) =>
      selection.isValid && !selection.isCollapsed
      ? widget.text.substring(selection.start, selection.end).trim()
      : '';

  Future<void> _addVocabulary(String selectedText) async {
    if (selectedText.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final vocabulary = await LocalDatabase.instance.addVocabulary(
        word: selectedText,
        contextId: widget.contextId,
        sourceText: widget.sourceText,
      );
      if (!mounted) return;
      widget.onVocabularyAdded?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added "${vocabulary.word}" to vocabulary.')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save vocabulary.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  @override
  Widget build(BuildContext context) => SelectableText(
    widget.text,
    style: widget.style,
    contextMenuBuilder: (context, editableTextState) {
      final selectedText = _selectedText(
        editableTextState.textEditingValue.selection,
      );
      final buttonItems = <ContextMenuButtonItem>[
        if (selectedText.isNotEmpty)
          ContextMenuButtonItem(
            label: 'Add vocab',
            onPressed: () {
              ContextMenuController.removeAny();
              _addVocabulary(selectedText);
            },
          ),
        ...editableTextState.contextMenuButtonItems,
      ];
      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: editableTextState.contextMenuAnchors,
        buttonItems: buttonItems,
      );
    },
  );
}
