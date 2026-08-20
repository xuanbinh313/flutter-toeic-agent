import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../services/import_questions_agent_service.dart';

class ImportQuestionsAgentWindow extends StatefulWidget {
  const ImportQuestionsAgentWindow({super.key, required this.examId});
  final String examId;

  @override
  State<ImportQuestionsAgentWindow> createState() =>
      _ImportQuestionsAgentWindowState();
}

class _ImportQuestionsAgentWindowState
    extends State<ImportQuestionsAgentWindow> {
  late final ImportQuestionsAgentService _service;
  bool _loading = false;
  String _progress = '';

  @override
  void initState() {
    super.initState();
    _service = ImportQuestionsAgentService(widget.examId);
  }

  Future<void> _pickAnswerSheet(bool listening) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final file = result?.files.single.path;
    if (file == null) {
      return;
    }
    setState(() {
      if (listening) {
        _service.listeningAnswerSheet = file;
      } else {
        _service.readingAnswerSheet = file;
      }
    });
  }

  Future<void> _pickPdf(ImportPartInput part, bool questions) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final file = result?.files.single.path;
    if (file == null) {
      return;
    }
    final pages = await _selectPages(
      file,
      questions ? part.questionPages : part.transcriptPages,
    );
    if (pages == null) return;
    setState(() {
      if (questions) {
        part.questionPdf = file;
        part.questionPages = pages;
      } else {
        part.transcriptPdf = file;
        part.transcriptPages = pages;
      }
    });
  }

  Future<List<int>?> _selectPages(String pdfPath, List<int> initial) async {
    final controller = TextEditingController(
      text: initial.map((page) => page + 1).join(', '),
    );
    final result = await showDialog<List<int>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select PDF pages'),
        content: SizedBox(
          width: 900,
          height: 620,
          child: Row(
            children: [
              Expanded(child: SfPdfViewer.file(File(pdfPath))),
              const SizedBox(width: 16),
              SizedBox(
                width: 250,
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Pages',
                    hintText: 'Example: 1, 3-5, 9',
                  ),
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
            onPressed: () {
              final pages = _parsePages(controller.text);
              if (pages.isEmpty) return;
              Navigator.pop(context, pages);
            },
            child: const Text('Save pages'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  List<int> _parsePages(String text) {
    final pages = <int>{};
    for (final token in text.split(',')) {
      final range = token.trim().split('-');
      final first = int.tryParse(range.first.trim());
      final last = int.tryParse(range.last.trim());
      if (first == null || last == null || first < 1 || last < first) continue;
      for (var page = first; page <= last; page++) {
        pages.add(page - 1);
      }
    }
    return pages.toList()..sort();
  }

  Future<void> _editPrompt(ImportPartInput part) async {
    final controller = TextEditingController(text: part.prompt);
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Part ${part.part} prompt'),
        content: SizedBox(
          width: 720,
          height: 460,
          child: TextField(
            controller: controller,
            expands: true,
            maxLines: null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved != null && saved.trim().isNotEmpty) {
      setState(() => part.prompt = saved.trim());
    }
  }

  Future<void> _send() async {
    setState(() => _loading = true);
    try {
      await _service.send(
        onProgress: (message) {
          if (mounted) {
            setState(() => _progress = message);
          }
        },
      );
      if (mounted) {
        _showMessage('Import complete. Groups and questions were saved.');
      }
    } catch (error) {
      if (mounted) {
        _showMessage('Import failed: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _showRequests() async {
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Agent requests'),
          content: SizedBox(
            width: 820,
            child: _service.requests.isEmpty
                ? const Text('No agent requests yet.')
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Part')),
                        DataColumn(label: Text('Created')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Attempts')),
                        DataColumn(label: Text('Error')),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows: _service.requests
                          .map(
                            (request) => DataRow(
                              cells: [
                                DataCell(Text('${request.part}')),
                                DataCell(
                                  Text(
                                    request.createdAt
                                        .toLocal()
                                        .toString()
                                        .substring(0, 19),
                                  ),
                                ),
                                DataCell(Text(request.status)),
                                DataCell(Text('${request.attempts}')),
                                DataCell(
                                  SizedBox(
                                    width: 220,
                                    child: Text(
                                      request.error,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Edit request prompt',
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: request.status == 'running'
                                            ? null
                                            : () async {
                                                await _editPrompt(
                                                  _service.parts[request.part -
                                                      1],
                                                );
                                                request.prompt = _service
                                                    .parts[request.part - 1]
                                                    .prompt;
                                                refresh(() {});
                                              },
                                      ),
                                      IconButton(
                                        tooltip: 'Retry request',
                                        icon: const Icon(Icons.refresh),
                                        onPressed: request.status == 'running'
                                            ? null
                                            : () async {
                                                try {
                                                  await _service.retry(
                                                    request,
                                                    onProgress: (message) {
                                                      if (mounted) {
                                                        setState(
                                                          () => _progress =
                                                              message,
                                                        );
                                                      }
                                                    },
                                                  );
                                                } catch (_) {}
                                                refresh(() {});
                                              },
                                      ),
                                      IconButton(
                                        tooltip: 'Remove request',
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: request.status == 'running'
                                            ? null
                                            : () {
                                                _service.requests.remove(
                                                  request,
                                                );
                                                refresh(() {});
                                              },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  void _showMessage(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1a73e8)),
    ),
    home: Scaffold(
      appBar: AppBar(title: const Text('Import Questions Agent')),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Listening'),
                Tab(text: 'Reading'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _section('Listening', 1, 4),
                  _section('Reading', 5, 7),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _progress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _showRequests,
                    icon: const Icon(Icons.list_alt),
                    label: const Text('Requests'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _loading ? null : _send,
                    icon: _loading
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.smart_toy_outlined),
                    label: Text(_loading ? 'Sending...' : 'Send to agent'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _section(String name, int start, int end) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _answerSheet(name, start <= 4),
      for (var part = start; part <= end; part++)
        _partCard(_service.parts[part - 1]),
    ],
  );

  Widget _answerSheet(String name, bool listening) {
    final value = listening
        ? _service.listeningAnswerSheet
        : _service.readingAnswerSheet;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.image_outlined),
        title: Text('$name answer sheet'),
        subtitle: Text(
          value.isEmpty
              ? 'No image selected'
              : value.split(RegExp(r'[\\/]')).last,
        ),
        trailing: IconButton(
          tooltip: 'Select answer-sheet image',
          onPressed: _loading ? null : () => _pickAnswerSheet(listening),
          icon: const Icon(Icons.attach_file),
        ),
      ),
    );
  }

  Widget _partCard(ImportPartInput part) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Part ${part.part}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (part.part != 2)
            _pdfRow(
              'Question pages',
              part.questionPdf,
              part.questionPages,
              () => _pickPdf(part, true),
            ),
          _pdfRow(
            'Transcript pages',
            part.transcriptPdf,
            part.transcriptPages,
            () => _pickPdf(part, false),
          ),
          if (part.part == 2)
            TextFormField(
              initialValue: part.contextText,
              onChanged: (value) => part.contextText = value,
              decoration: const InputDecoration(labelText: 'Question context'),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  part.prompt.replaceAll('\n', ' '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Edit part prompt',
                onPressed: _loading ? null : () => _editPrompt(part),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _pdfRow(
    String label,
    String file,
    List<int> pages,
    VoidCallback select,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(
      file.isEmpty
          ? 'No PDF selected'
          : '${file.split(RegExp(r'[\\/]')).last}: pages ${pages.map((page) => page + 1).join(', ')}',
    ),
    trailing: OutlinedButton.icon(
      onPressed: _loading ? null : select,
      icon: const Icon(Icons.picture_as_pdf_outlined),
      label: const Text('Select'),
    ),
  );
}

Future<Widget> importWindowForArguments(String rawArguments) async {
  final arguments = jsonDecode(rawArguments) as Map<String, dynamic>;
  return ImportQuestionsAgentWindow(examId: arguments['examId'] as String);
}
