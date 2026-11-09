import 'package:flutter/material.dart';

class TranscriptToolbar extends StatelessWidget {
  const TranscriptToolbar({
    super.key,
    required this.isDetecting,
    required this.isTranslating,
    required this.isValidating,
    required this.hasChanges,
    required this.hasSelection,
    required this.onDetect,
    required this.onValidate,
    required this.onTranslate,
    required this.onSplit,
    required this.onSave,
  });

  final bool isDetecting;
  final bool isTranslating;
  final bool isValidating;
  final bool hasChanges;
  final bool hasSelection;
  final VoidCallback onDetect;
  final VoidCallback onValidate;
  final VoidCallback onTranslate;
  final VoidCallback onSplit;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 150,
          child: Text(
            'Transcript chunks',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
        ),
        OutlinedButton.icon(
          onPressed: isDetecting ? null : onDetect,
          icon: const Icon(Icons.auto_awesome),
          label: Text(isDetecting ? 'Detecting audio...' : 'Auto-detect Audio'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: isValidating ? null : onValidate,
          icon: const Icon(Icons.fact_check_outlined),
          label: Text(isValidating ? 'Validating...' : 'Validate transcript'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: isTranslating ? null : onTranslate,
          icon: const Icon(Icons.translate),
          label: Text(
            isTranslating ? 'Translating...' : 'Translate to Vietnamese',
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: hasSelection ? onSplit : null,
          icon: const Icon(Icons.call_split),
          label: const Text('Split at cursor'),
        ),
        if (hasChanges) ...[
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.save),
            label: const Text('Save'),
          ),
        ],
      ],
    ),
  );
}
