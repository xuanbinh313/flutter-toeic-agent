import 'package:flutter/material.dart';

class ImportAnswerSheetPanel extends StatelessWidget {
  const ImportAnswerSheetPanel({
    super.key,
    required this.title,
    required this.imagePath,
    required this.loading,
    required this.onPick,
    this.onPaste,
  });

  final String title;
  final String imagePath;
  final bool loading;
  final VoidCallback onPick;
  final VoidCallback? onPaste;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.image_outlined),
      title: Text('$title answer sheet'),
      subtitle: Text(
        imagePath.isEmpty
            ? 'No image selected'
            : imagePath.split(RegExp(r'[\\/]')).last,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onPaste != null)
            IconButton(
              tooltip: 'Paste image from clipboard',
              onPressed: loading ? null : onPaste,
              icon: const Icon(Icons.content_paste),
            ),
          IconButton(
            tooltip: 'Select answer-sheet image',
            onPressed: loading ? null : onPick,
            icon: const Icon(Icons.attach_file),
          ),
        ],
      ),
    ),
  );
}
