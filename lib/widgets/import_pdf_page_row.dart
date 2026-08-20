import 'package:flutter/material.dart';

class ImportPdfPageRow extends StatelessWidget {
  const ImportPdfPageRow({
    super.key,
    required this.label,
    required this.filePath,
    required this.pages,
    required this.loading,
    required this.onSelect,
  });

  final String label;
  final String filePath;
  final List<int> pages;
  final bool loading;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(
      filePath.isEmpty
          ? 'No PDF selected'
          : '${filePath.split(RegExp(r'[\\/]')).last}: pages ${pages.map((page) => page + 1).join(', ')}',
    ),
    trailing: OutlinedButton.icon(
      onPressed: loading ? null : onSelect,
      icon: const Icon(Icons.picture_as_pdf_outlined),
      label: const Text('Select'),
    ),
  );
}
