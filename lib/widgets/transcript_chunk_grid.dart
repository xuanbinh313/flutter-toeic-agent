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
      _timeColumn('Start', 'start'),
      _timeColumn('End', 'end'),
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

  PlutoColumn _timeColumn(String title, String field) => PlutoColumn(
    title: title,
    field: field,
    type: PlutoColumnType.number(),
    width: 145,
    enableEditingMode: false,
    renderer: (context) {
      final id = context.row.cells['id']!.value as String;
      final value = (context.cell.value as num).toDouble();
      return Row(
        children: [
          IconButton(
            iconSize: 17,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            tooltip: 'Decrease $title',
            onPressed: () => _changeTime(context, id, field, value - .1),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Expanded(
            child: _TimeEditor(
              key: ValueKey('$id-$field'),
              value: value,
              onChanged: (changed) => _changeTime(context, id, field, changed),
            ),
          ),
          IconButton(
            iconSize: 17,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            tooltip: 'Increase $title',
            onPressed: () => _changeTime(context, id, field, value + .1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      );
    },
  );

  double _changeTime(
    PlutoColumnRendererContext context,
    String id,
    String field,
    double value,
  ) {
    final updated = widget.onTimeChanged(id, field, value);
    context.stateManager.changeCellValue(
      context.cell,
      updated,
      callOnChangedEvent: false,
    );
    return updated;
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
}

class _TimeEditor extends StatefulWidget {
  const _TimeEditor({super.key, required this.value, required this.onChanged});

  final double value;
  final double Function(double value) onChanged;

  @override
  State<_TimeEditor> createState() => _TimeEditorState();
}

class _TimeEditorState extends State<_TimeEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
    _focusNode = FocusNode()..addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _TimeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focusNode.hasFocus) {
      _setText(widget.value);
    }
  }

  static String _format(double value) => value.toStringAsFixed(2);

  void _setText(double value) {
    final text = _format(value);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) _commit();
  }

  void _commit() {
    final changed = double.tryParse(_controller.text.trim());
    if (changed == null) {
      _setText(widget.value);
      return;
    }
    _setText(widget.onChanged(changed));
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    focusNode: _focusNode,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    textAlign: TextAlign.center,
    decoration: const InputDecoration(isDense: true, border: InputBorder.none),
    onSubmitted: (_) => _commit(),
    onEditingComplete: _commit,
  );

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }
}
