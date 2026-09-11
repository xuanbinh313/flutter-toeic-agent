import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pasteboard/pasteboard.dart';

import '../services/import_questions_agent_service.dart';
import '../widgets/import_answer_sheet_panel.dart';
import '../widgets/import_overall_pdf_source_panel.dart';
import '../widgets/import_pdf_page_row.dart';
import '../widgets/pdf_page_selector_dialog.dart';

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
  final _requestsScrollController = ScrollController();
  final _requestsHorizontalScrollController = ScrollController();
  bool _loading = false;
  String _progress = '';

  @override
  void initState() {
    super.initState();
    _service = ImportQuestionsAgentService(widget.examId);
    _restoreRequests();
  }

  Future<void> _restoreRequests() async {
    await _service.loadRequests();
    if (mounted) setState(() {});
  }

  Future<void> _pickAnswerSheet(bool listening) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final file = result?.files.single.path;
    if (file == null) {
      return;
    }
    if (!mounted) {
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

  Future<void> _pasteAnswerSheet(bool listening) async {
    final label = listening ? 'Listening' : 'Reading/Writing';
    try {
      final bytes = await Pasteboard.image;
      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          _showMessage('Clipboard does not contain an image.');
        }
        return;
      }
      final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'junedu-${listening ? 'listening' : 'reading'}-answer-'
        '${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes, flush: true);
      if (mounted) {
        setState(() {
          if (listening) {
            _service.listeningAnswerSheet = file.path;
          } else {
            _service.readingAnswerSheet = file.path;
          }
        });
        _showMessage('$label answer sheet pasted from the clipboard.');
      }
    } catch (error) {
      if (mounted) {
        _showMessage('Could not paste the $label answer sheet: $error');
      }
    }
  }

  Future<void> _pickOverallPdf(String section, String lane) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final file = result?.files.single.path;
    if (file == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    final pages = await PdfPageSelectorDialog.show(
      context,
      pdfPath: file,
      initialPages: _service.sources[section]![lane]!.path == file
          ? _service.sources[section]![lane]!.pages
          : const [],
    );
    if (pages == null || !mounted) {
      return;
    }
    String tempPath;
    try {
      tempPath = await _service.prepareOverallSourcePdf(
        section: section,
        lane: lane,
        sourcePath: file,
        selectedPages: pages,
      );
    } catch (error) {
      if (mounted) {
        _showMessage('Could not prepare the source PDF: $error');
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      final source = _service.sources[section]![lane]!;
      source
        ..path = file
        ..pages = pages
        ..tempPath = tempPath;
      for (final part in _service.parts) {
        if ((part.part <= 4 ? 'listening' : 'reading') != section) {
          continue;
        }
        if (lane == 'questions') {
          part
            ..questionPdf = ''
            ..questionPages = [];
        } else {
          part
            ..transcriptPdf = ''
            ..transcriptPages = [];
        }
      }
    });
  }

  Future<void> _selectPartPages(ImportPartInput part, String lane) async {
    final section = part.part <= 4 ? 'listening' : 'reading';
    final source = _service.sources[section]![lane]!;
    if (!source.isSelected) {
      _showMessage(
        'Select the overall ${lane == 'questions' ? 'question' : 'transcript'} PDF first.',
      );
      return;
    }
    final initial = lane == 'questions'
        ? part.questionPages
        : part.transcriptPages;
    final pages = await PdfPageSelectorDialog.show(
      context,
      pdfPath: source.tempPath,
      initialPages: initial,
    );
    if (pages == null) {
      return;
    }
    setState(() {
      if (lane == 'questions') {
        part
          ..questionPdf = source.tempPath
          ..questionPages = pages;
      } else {
        part
          ..transcriptPdf = source.tempPath
          ..transcriptPages = pages;
      }
    });
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
      await _service.saveRequests();
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
        final saved = _service.requests.isEmpty
            ? ''
            : _service.requests.last.responsePath;
        _showMessage(
          saved.isEmpty
              ? 'Import complete. Groups and questions were saved.'
              : 'Import complete. Response saved to: $saved',
        );
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
    var retryingAll = false;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Agent requests'),
          content: SizedBox(
            width: 820,
            height: 500,
            child: _service.requests.isEmpty
                ? const Text('No agent requests yet.')
                : Scrollbar(
                    controller: _requestsScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _requestsScrollController,
                      child: Scrollbar(
                        controller: _requestsHorizontalScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _requestsHorizontalScrollController,
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 1100),
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Part')),
                                // DataColumn(label: Text('Created')),
                                DataColumn(label: Text('Status')),
                                DataColumn(label: Text('Attempts')),
                                DataColumn(label: Text('Error')),
                                // DataColumn(label: Text('Response JSON')),
                                DataColumn(label: Text('Actions')),
                              ],
                              rows: _service.requests
                                  .map(
                                    (request) => DataRow(
                                      cells: [
                                        DataCell(Text('${request.part}')),
                                        // DataCell(
                                        //   Text(
                                        //     request.createdAt
                                        //         .toLocal()
                                        //         .toString()
                                        //         .substring(0, 19),
                                        //   ),
                                        // ),
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
                                        // DataCell(
                                        //   SizedBox(
                                        //     width: 260,
                                        //     child: Text(
                                        //       request.responsePath,
                                        //       overflow: TextOverflow.ellipsis,
                                        //     ),
                                        //   ),
                                        // ),
                                        DataCell(
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                tooltip: 'Edit request prompt',
                                                icon: const Icon(
                                                  Icons.edit_outlined,
                                                ),
                                                onPressed:
                                                    request.status == 'running'
                                                    ? null
                                                    : () async {
                                                        await _editPrompt(
                                                          _service.parts[request
                                                                  .part -
                                                              1],
                                                        );
                                                        request.prompt =
                                                            _service
                                                                .parts[request
                                                                        .part -
                                                                    1]
                                                                .prompt;
                                                        refresh(() {});
                                                      },
                                              ),
                                              OutlinedButton.icon(
                                                icon: const Icon(Icons.refresh),
                                                label: const Text('Retry'),
                                                onPressed:
                                                    request.status == 'running'
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
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                ),
                                                onPressed:
                                                    request.status == 'running'
                                                    ? null
                                                    : () {
                                                        _service.requests
                                                            .remove(request);
                                                        _service.saveRequests();
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
                      ),
                    ),
                  ),
          ),
          actions: [
            FilledButton.icon(
              onPressed:
                  retryingAll ||
                      !_service.requests.any(
                        (request) => request.status != 'running',
                      )
                  ? null
                  : () async {
                      retryingAll = true;
                      refresh(() {});
                      for (final request in List<AgentRequest>.from(
                        _service.requests,
                      )) {
                        if (request.status == 'running') continue;
                        try {
                          await _service.retry(
                            request,
                            onProgress: (message) {
                              if (mounted) {
                                setState(() => _progress = message);
                              }
                            },
                          );
                        } catch (_) {
                          // Keep retrying the remaining requests.
                        }
                        refresh(() {});
                      }
                      retryingAll = false;
                      refresh(() {});
                    },
              icon: retryingAll
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(retryingAll ? 'Retrying...' : 'Retry all'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _requestsScrollController.dispose();
    _requestsHorizontalScrollController.dispose();
    super.dispose();
  }

  void _showMessage(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
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
  );

  Widget _section(String name, int start, int end) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      ImportAnswerSheetPanel(
        title: name,
        imagePath: start <= 4
            ? _service.listeningAnswerSheet
            : _service.readingAnswerSheet,
        loading: _loading,
        onPick: () => _pickAnswerSheet(start <= 4),
        onPaste: () => _pasteAnswerSheet(start <= 4),
      ),
      ImportOverallPdfSourcePanel(
        questionSource: _service
            .sources[start <= 4 ? 'listening' : 'reading']!['questions']!,
        transcriptSource: _service
            .sources[start <= 4 ? 'listening' : 'reading']!['transcripts']!,
        loading: _loading,
        onPickQuestions: () =>
            _pickOverallPdf(start <= 4 ? 'listening' : 'reading', 'questions'),
        onPickTranscripts: () => _pickOverallPdf(
          start <= 4 ? 'listening' : 'reading',
          'transcripts',
        ),
      ),
      for (var part = start; part <= end; part++)
        _partCard(_service.parts[part - 1]),
    ],
  );

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
            ImportPdfPageRow(
              label: 'Question pages',
              filePath: part.questionPdf,
              pages: part.questionPages,
              loading: _loading,
              onSelect: () => _selectPartPages(part, 'questions'),
            ),
          ImportPdfPageRow(
            label: 'Transcript pages',
            filePath: part.transcriptPdf,
            pages: part.transcriptPages,
            loading: _loading,
            onSelect: () => _selectPartPages(part, 'transcripts'),
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
}
