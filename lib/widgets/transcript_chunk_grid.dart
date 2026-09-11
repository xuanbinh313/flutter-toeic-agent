import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../models.dart';

class TranscriptChunkGrid extends StatefulWidget {
  const TranscriptChunkGrid({
    super.key,
    required this.chunks,
    required this.isLoaded,
    required this.onTimeChanged,
    required this.onTextChanged,
    required this.onAction,
    required this.onSelected,
  });

  final List<SrtChunk> chunks;
  final bool isLoaded;
  final double Function(String id, String field, double value) onTimeChanged;
  final void Function(String id, String text) onTextChanged;
  final Future<void> Function(String id, String action) onAction;
  final ValueChanged<String> onSelected;

  @override
  State<TranscriptChunkGrid> createState() => _TranscriptChunkGridState();
}

class _TranscriptChunkGridState extends State<TranscriptChunkGrid> {
  static const _pageSize = 30;
  PlutoGridStateManager? _stateManager;

  @override
  Widget build(BuildContext context) => PlutoGrid(
    key: ValueKey(widget.isLoaded),
    columns: [
      PlutoColumn(
        title: '#',
        field: 'number',
        type: PlutoColumnType.number(),
        width: 55,
        enableEditingMode: false,
      ),
      PlutoColumn(
        title: 'Start',
        field: 'start',
        type: PlutoColumnType.number(format: '#,##0.##'),
        width: 145,
      ),
      PlutoColumn(
        title: 'End',
        field: 'end',
        type: PlutoColumnType.number(format: '#,##0.##'),
        width: 145,
      ),
      PlutoColumn(
        title: 'Transcript',
        field: 'text',
        type: PlutoColumnType.text(),
        width: 480,
        minWidth: 320,
      ),
      PlutoColumn(
        title: 'Note',
        field: 'note',
        type: PlutoColumnType.text(),
        minWidth: 240,
        enableEditingMode: false,
        renderer: _bodyText,
      ),
      PlutoColumn(
        title: 'Actions',
        field: 'actions',
        type: PlutoColumnType.text(),
        width: 320,
        enableEditingMode: false,
        renderer: _actions,
      ),
    ],
    // Keep this mutable, as PlutoInfinityScrollRows appends each fetched page.
    rows: [],
    createFooter: (stateManager) => PlutoInfinityScrollRows(
      stateManager: stateManager,
      fetch: _fetchRows,
      fetchWithFiltering: false,
      fetchWithSorting: false,
    ),
    onLoaded: (event) => _stateManager = event.stateManager,
    onChanged: (event) {
      if (event.column.field == 'text') {
        widget.onTextChanged(
          event.row.cells['id']!.value as String,
          '${event.value}',
        );
      }
    },
    onSelected: (event) {
      final row = event.row;
      if (row != null) widget.onSelected(row.cells['id']!.value as String);
    },
    configuration: const PlutoGridConfiguration(
      style: PlutoGridStyleConfig(rowHeight: 42, columnHeight: 32),
      scrollbar: PlutoGridScrollbarConfig(
        draggableScrollbar: true,
        isAlwaysShown: true,
        scrollbarThickness: 8,
      ),
      columnSize: PlutoGridColumnSizeConfig(
        autoSizeMode: PlutoAutoSizeMode.none,
      ),
    ),
    mode: PlutoGridMode.normal,
  );

  Future<PlutoInfinityScrollRowsResponse> _fetchRows(
    PlutoInfinityScrollRowsRequest request,
  ) async {
    final lastId = request.lastRow?.cells['id']?.value as String?;
    final start = lastId == null
        ? 0
        : widget.chunks.indexWhere((chunk) => chunk.id == lastId) + 1;
    final safeStart = start < 0 ? 0 : start;
    final end = (safeStart + _pageSize).clamp(0, widget.chunks.length).toInt();
    return PlutoInfinityScrollRowsResponse(
      rows: _rows(widget.chunks.sublist(safeStart, end), safeStart),
      isLast: end >= widget.chunks.length,
    );
  }

  List<PlutoRow> _rows(List<SrtChunk> chunks, int offset) => [
    for (var i = 0; i < chunks.length; i++)
      PlutoRow(
        cells: {
          'id': PlutoCell(value: chunks[i].id),
          'number': PlutoCell(value: offset + i + 1),
          'start': PlutoCell(value: chunks[i].start),
          'end': PlutoCell(value: chunks[i].end),
          'text': PlutoCell(value: chunks[i].text),
          'note': PlutoCell(value: chunks[i].hint ?? ''),
          'actions': PlutoCell(value: ''),
        },
      ),
  ];

  Future<void> _runAction(String id, String action) async {
    if (action == 'edit_time') {
      await _editTime(id);
      return;
    }
    await widget.onAction(id, action);
    if (!mounted || !_changesRows(action)) return;
    _syncLoadedRows();
  }

  bool _changesRows(String action) => switch (action) {
    'merge' || 'duplicate' || 'split' || 'delete' => true,
    _ => false,
  };

  void _syncLoadedRows() {
    final stateManager = _stateManager;
    if (stateManager == null) return;
    final existing = stateManager.refRows.originalList.toList();
    if (existing.isEmpty) return;
    final existingIds = existing
        .map((row) => row.cells['id']!.value as String)
        .toSet();
    final lastLoadedIndex = widget.chunks.lastIndexWhere(
      (chunk) => existingIds.contains(chunk.id),
    );
    if (lastLoadedIndex < 0) {
      stateManager.removeRows(existing);
      return;
    }
    final target = widget.chunks.sublist(0, lastLoadedIndex + 1);
    final targetIds = target.map((chunk) => chunk.id).toSet();
    stateManager.removeRows(
      existing
          .where((row) => !targetIds.contains(row.cells['id']!.value))
          .toList(),
      notify: false,
    );

    for (var index = 0; index < target.length; index++) {
      final chunk = target[index];
      final rows = stateManager.refRows.originalList;
      final current = index < rows.length ? rows[index] : null;
      if (current?.cells['id']!.value != chunk.id) {
        stateManager.insertRows(index, _rows([chunk], index), notify: false);
      } else {
        _updateRow(stateManager, current!, chunk, index);
      }
    }
    stateManager.notifyListeners();
  }

  void _updateRow(
    PlutoGridStateManager stateManager,
    PlutoRow row,
    SrtChunk chunk,
    int index,
  ) {
    final values = {
      'number': index + 1,
      'start': chunk.start,
      'end': chunk.end,
      'text': chunk.text,
      'note': chunk.hint ?? '',
    };
    for (final entry in values.entries) {
      final cell = row.cells[entry.key]!;
      if (cell.value != entry.value) {
        stateManager.changeCellValue(
          cell,
          entry.value,
          callOnChangedEvent: false,
          notify: false,
        );
      }
    }
  }

  Widget _bodyText(PlutoColumnRendererContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      '${context.cell.value ?? ''}',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12),
    ),
  );

  Widget _actions(PlutoColumnRendererContext context) {
    final id = context.row.cells['id']!.value as String;
    return Row(
      children: [
        _action(id, Icons.access_time, 'Edit time', 'edit_time'),
        _action(id, Icons.play_arrow, 'Play', 'play'),
        _action(id, Icons.repeat, 'Repeat', 'repeat'),
        _action(id, Icons.merge, 'Merge next', 'merge'),
        _action(id, Icons.copy, 'Duplicate', 'duplicate'),
        _action(id, Icons.call_split, 'Split at cursor', 'split'),
        _action(id, Icons.delete_outline, 'Delete', 'delete'),
      ],
    );
  }

  Widget _action(String id, IconData icon, String tooltip, String action) =>
      IconButton(
        iconSize: 18,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 42, height: 30),
        tooltip: tooltip,
        onPressed: () => _runAction(id, action),
        icon: Icon(icon),
      );

  Future<void> _editTime(String id) async {
    final chunk = widget.chunks.firstWhere((chunk) => chunk.id == id);
    final result = await showDialog<({double start, double end})>(
      context: context,
      builder: (context) =>
          _TimeRangeDialog(start: chunk.start, end: chunk.end),
    );
    if (!mounted || result == null) return;

    // Update End first so the parent validation can accept a larger Start.
    final end = widget.onTimeChanged(id, 'end', result.end);
    final start = widget.onTimeChanged(id, 'start', result.start);
    final row = _stateManager?.refRows.originalList
        .cast<PlutoRow?>()
        .firstWhere((row) => row?.cells['id']?.value == id, orElse: () => null);
    if (row == null) return;
    _stateManager?.changeCellValue(row.cells['end']!, end, force: true);
    _stateManager?.changeCellValue(row.cells['start']!, start, force: true);
  }
}

class _TimeRangeDialog extends StatefulWidget {
  const _TimeRangeDialog({required this.start, required this.end});

  final double start;
  final double end;

  @override
  State<_TimeRangeDialog> createState() => _TimeRangeDialogState();
}

class _TimeRangeDialogState extends State<_TimeRangeDialog> {
  late final TextEditingController _startController;
  late final TextEditingController _endController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startController = TextEditingController(text: widget.start.toString());
    _endController = TextEditingController(text: widget.end.toString());
  }

  void _save() {
    final start = double.tryParse(_startController.text.trim());
    final end = double.tryParse(_endController.text.trim());
    if (start == null || end == null || start < 0 || end < start) {
      setState(() => _error = 'Enter valid times where End is at least Start.');
      return;
    }
    Navigator.of(context).pop((start: start, end: end));
  }

  void _adjust(TextEditingController controller, double amount) {
    final value = double.tryParse(controller.text.trim()) ?? 0;
    final updated = value + amount;
    final text = updated.toStringAsFixed(2);
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() => _error = null);
  }

  Widget _timeField(String label, TextEditingController controller) => Row(
    children: [
      IconButton(
        tooltip: 'Decrease $label by 0.1 seconds',
        onPressed: () => _adjust(controller, -0.1),
        icon: const Icon(Icons.remove_circle_outline),
      ),
      Expanded(
        child: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label),
        ),
      ),
      IconButton(
        tooltip: 'Increase $label by 0.1 seconds',
        onPressed: () => _adjust(controller, 0.1),
        icon: const Icon(Icons.add_circle_outline),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit time'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _timeField('Start', _startController),
        _timeField('End', _endController),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }
}
