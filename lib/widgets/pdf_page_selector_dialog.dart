import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class PdfPageSelectorDialog extends StatefulWidget {
  const PdfPageSelectorDialog({
    super.key,
    required this.pdfPath,
    required this.initialPages,
  });

  final String pdfPath;
  final List<int> initialPages;

  static Future<List<int>?> show(
    BuildContext context, {
    required String pdfPath,
    required List<int> initialPages,
  }) => showDialog<List<int>>(
    context: context,
    builder: (_) =>
        PdfPageSelectorDialog(pdfPath: pdfPath, initialPages: initialPages),
  );

  @override
  State<PdfPageSelectorDialog> createState() => _PdfPageSelectorDialogState();
}

class _PdfPageSelectorDialogState extends State<PdfPageSelectorDialog> {
  late final TextEditingController _pagesController;
  final _pagesFocusNode = FocusNode();
  final _viewerController = PdfViewerController();
  Timer? _pageJumpDebounce;
  late final Set<int> _selectedPages;
  late int _currentPage;

  @override
  void initState() {
    super.initState();
    _selectedPages = widget.initialPages.toSet();
    _pagesController = TextEditingController(text: _pageText(_selectedPages));
    _currentPage = widget.initialPages.isEmpty
        ? 1
        : widget.initialPages.first + 1;
  }

  @override
  void dispose() {
    _pagesController.dispose();
    _pagesFocusNode.dispose();
    _pageJumpDebounce?.cancel();
    _viewerController.dispose();
    super.dispose();
  }

  void _setSelectedPages(Set<int> pages) {
    setState(() {
      _selectedPages
        ..clear()
        ..addAll(pages);
      _pagesController.text = _pageText(_selectedPages);
    });
  }

  void _changePage(int page) {
    _viewerController.jumpToPage(page);
    setState(() => _currentPage = page);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Select PDF pages'),
    content: SizedBox(
      width: 900,
      height: 620,
      child: Row(
        children: [
          Expanded(
            child: SfPdfViewer.file(
              File(widget.pdfPath),
              controller: _viewerController,
              initialPageNumber: _currentPage,
              onPageChanged: (details) =>
                  setState(() => _currentPage = details.newPageNumber),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 250,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Current page: $_currentPage'),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _toggleCurrentPage,
                  icon: Icon(
                    _selectedPages.contains(_currentPage - 1)
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                  ),
                  label: Text(
                    _selectedPages.contains(_currentPage - 1)
                        ? 'Remove current page'
                        : 'Select current page',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pagesController,
                  focusNode: _pagesFocusNode,
                  decoration: const InputDecoration(
                    labelText: 'Selected pages',
                    hintText: 'Example: 1, 3-5, 9',
                  ),
                  onChanged: _updateFromText,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final page in _selectedPages.toList()..sort())
                      InputChip(
                        label: Text('${page + 1}'),
                        onPressed: () => _changePage(page + 1),
                        onDeleted: () => _setSelectedPages(
                          {..._selectedPages}..remove(page),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _selectedPages.isEmpty
            ? null
            : () => Navigator.pop(context, _selectedPages.toList()..sort()),
        child: const Text('Save pages'),
      ),
    ],
  );

  void _toggleCurrentPage() {
    final pages = {..._selectedPages};
    if (!pages.add(_currentPage - 1)) {
      pages.remove(_currentPage - 1);
    }
    _setSelectedPages(pages);
  }

  void _updateFromText(String value) {
    final pages = _parsePages(value).toSet();
    setState(() {
      _selectedPages
        ..clear()
        ..addAll(pages);
    });
    _pageJumpDebounce?.cancel();
    if (pages.isNotEmpty) {
      final targetPage = pages.last + 1;
      _pageJumpDebounce = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) {
          return;
        }
        _viewerController.jumpToPage(targetPage);
        _pagesFocusNode.requestFocus();
      });
    }
  }

  String _pageText(Iterable<int> pages) =>
      pages.map((page) => page + 1).join(', ');

  List<int> _parsePages(String text) {
    final pages = <int>{};
    for (final token in text.split(',')) {
      final range = token.trim().split('-');
      final first = int.tryParse(range.first.trim());
      final last = int.tryParse(range.last.trim());
      if (first == null || last == null || first < 1 || last < first) {
        continue;
      }
      for (var page = first; page <= last; page++) {
        pages.add(page - 1);
      }
    }
    return pages.toList()..sort();
  }
}
