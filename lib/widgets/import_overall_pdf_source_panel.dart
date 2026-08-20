import 'package:flutter/material.dart';

import '../services/import_questions_agent_service.dart';

class ImportOverallPdfSourcePanel extends StatelessWidget {
  const ImportOverallPdfSourcePanel({
    super.key,
    required this.questionSource,
    required this.transcriptSource,
    required this.loading,
    required this.onPickQuestions,
    required this.onPickTranscripts,
  });

  final OverallPdfSource questionSource;
  final OverallPdfSource transcriptSource;
  final bool loading;
  final VoidCallback onPickQuestions;
  final VoidCallback onPickTranscripts;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Overall PDF Source Files',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          _sourceRow('Question PDF', questionSource, onPickQuestions),
          _sourceRow('Transcript PDF', transcriptSource, onPickTranscripts),
        ],
      ),
    ),
  );

  Widget _sourceRow(
    String label,
    OverallPdfSource source,
    VoidCallback onPick,
  ) {
    final summary = source.isSelected
        ? '${source.path.split(RegExp(r'[\\/]')).last}: pages ${source.pages.map((page) => page + 1).join(', ')} -> ${source.tempPath.split(RegExp(r'[\\/]')).last}'
        : 'No ${label.toLowerCase()} selected';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: OutlinedButton.icon(
        onPressed: loading ? null : onPick,
        icon: const Icon(Icons.picture_as_pdf_outlined),
        label: const Text('Select'),
      ),
    );
  }
}
