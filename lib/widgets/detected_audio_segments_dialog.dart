import 'package:flutter/material.dart';

import '../models.dart';

Future<List<DetectedAudioSegment>?> showDetectedAudioSegmentsDialog(
  BuildContext context,
  List<DetectedAudioSegment> segments,
) => showDialog<List<DetectedAudioSegment>>(
  context: context,
  builder: (_) => _DetectedAudioSegmentsDialog(segments: segments),
);

class _DetectedAudioSegmentsDialog extends StatefulWidget {
  const _DetectedAudioSegmentsDialog({required this.segments});
  final List<DetectedAudioSegment> segments;

  @override
  State<_DetectedAudioSegmentsDialog> createState() =>
      _DetectedAudioSegmentsDialogState();
}

class _DetectedAudioSegmentsDialogState
    extends State<_DetectedAudioSegmentsDialog> {
  late final Set<String> _selected = widget.segments
      .map((item) => item.context.id)
      .toSet();

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Review detected audio segments'),
    content: SizedBox(
      width: 680,
      child: ListView(
        shrinkWrap: true,
        children: widget.segments
            .map(
              (segment) => CheckboxListTile(
                value: _selected.contains(segment.context.id),
                onChanged: (checked) => setState(() {
                  if (checked ?? false) {
                    _selected.add(segment.context.id);
                  } else {
                    _selected.remove(segment.context.id);
                  }
                }),
                title: Text(
                  'Part ${segment.context.part} · ${_label(segment.context)}',
                ),
                subtitle: Text(
                  '${segment.start.toStringAsFixed(2)} – ${segment.end.toStringAsFixed(2)} seconds',
                ),
              ),
            )
            .toList(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          widget.segments
              .where((item) => _selected.contains(item.context.id))
              .toList(),
        ),
        child: const Text('Save selected'),
      ),
    ],
  );

  String _label(ExamContext context) {
    final numbers =
        context.questions.map((question) => question.number).toList()..sort();
    if (numbers.isEmpty) {
      return context.type.isEmpty
          ? 'Context ${context.index + 1}'
          : context.type;
    }
    return numbers.length == 1
        ? 'Question ${numbers.single}'
        : 'Questions ${numbers.first}–${numbers.last}';
  }
}
