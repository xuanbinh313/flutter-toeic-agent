import 'package:flutter/material.dart';

import '../services/import_questions_agent_service.dart';

class ImportAgentRequestsDialog extends StatefulWidget {
  const ImportAgentRequestsDialog({
    super.key,
    required this.service,
    required this.onEditPrompt,
    required this.onProgress,
  });

  final ImportQuestionsAgentService service;
  final Future<void> Function(ImportPartInput part) onEditPrompt;
  final ValueChanged<String> onProgress;

  @override
  State<ImportAgentRequestsDialog> createState() =>
      _ImportAgentRequestsDialogState();
}

class _ImportAgentRequestsDialogState extends State<ImportAgentRequestsDialog> {
  final _verticalController = ScrollController();
  final _horizontalController = ScrollController();
  bool _retryingAll = false;

  ImportQuestionsAgentService get _service => widget.service;

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Agent requests'),
    content: SizedBox(
      width: 820,
      height: 500,
      child: _service.requests.isEmpty
          ? const Text('No agent requests yet.')
          : Scrollbar(
              controller: _verticalController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _verticalController,
                child: Scrollbar(
                  controller: _horizontalController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _horizontalController,
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 1100),
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Part')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Attempts')),
                          DataColumn(label: Text('Error')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: _service.requests.map(_requestRow).toList(),
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
            _retryingAll ||
                !_service.requests.any((request) => request.status != 'running')
            ? null
            : _retryAll,
        icon: _retryingAll
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh),
        label: Text(_retryingAll ? 'Retrying...' : 'Retry all'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );

  DataRow _requestRow(AgentRequest request) => DataRow(
    cells: [
      DataCell(Text('${request.part}')),
      DataCell(Text(request.status)),
      DataCell(Text('${request.attempts}')),
      DataCell(
        SizedBox(
          width: 220,
          child: Text(request.error, overflow: TextOverflow.ellipsis),
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
                  : () => _editRequestPrompt(request),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              onPressed: request.status == 'running'
                  ? null
                  : () => _retry(request),
            ),
            IconButton(
              tooltip: 'Remove request',
              icon: const Icon(Icons.delete_outline),
              onPressed: request.status == 'running'
                  ? null
                  : () {
                      _service.requests.remove(request);
                      _service.saveRequests();
                      setState(() {});
                    },
            ),
          ],
        ),
      ),
    ],
  );

  Future<void> _editRequestPrompt(AgentRequest request) async {
    final part = _service.parts[request.part - 1];
    await widget.onEditPrompt(part);
    request.prompt = part.prompt;
    if (mounted) setState(() {});
  }

  Future<void> _retry(AgentRequest request) async {
    try {
      await _service.retry(request, onProgress: widget.onProgress);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _retryAll() async {
    setState(() => _retryingAll = true);
    for (final request in List<AgentRequest>.from(_service.requests)) {
      if (request.status == 'running') continue;
      try {
        await _service.retry(request, onProgress: widget.onProgress);
      } catch (_) {
        // Continue retrying the remaining requests.
      }
      if (mounted) setState(() {});
    }
    if (mounted) setState(() => _retryingAll = false);
  }
}
