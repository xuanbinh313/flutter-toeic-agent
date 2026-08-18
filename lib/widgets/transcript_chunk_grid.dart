import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../models.dart';

class TranscriptChunkGrid extends StatefulWidget {
  const TranscriptChunkGrid({
    super.key,
    required this.chunks,
    required this.onTimeChanged,
    required this.onTextChanged,
    required this.onAction,
    required this.onSelected,
  });

  final List<SrtChunk> chunks;
  final void Function(String id, String field, double value) onTimeChanged;
  final void Function(String id, String text) onTextChanged;
  final Future<void> Function(String id, String action) onAction;
  final ValueChanged<String> onSelected;

  @override
  State<TranscriptChunkGrid> createState() => _TranscriptChunkGridState();
}

class _TranscriptChunkGridState extends State<TranscriptChunkGrid> {
  PlutoGridStateManager? _stateManager;
  String _appliedStructure = '';

  @override
  void didUpdateWidget(covariant TranscriptChunkGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncRows());
  }

  @override
  Widget build(BuildContext context) => PlutoGrid(
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
        minWidth: 260,
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
    rows: _rows,
    onLoaded: (event) {
      _stateManager = event.stateManager;
      _appliedStructure = _structureVersion;
    },
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
    ),
  );

  String get _structureVersion =>
      widget.chunks.map((chunk) => chunk.id).join('|');

  List<PlutoRow> get _rows => [
    for (var i = 0; i < widget.chunks.length; i++)
      PlutoRow(
        cells: {
          'id': PlutoCell(value: widget.chunks[i].id),
          'number': PlutoCell(value: i + 1),
          'start': PlutoCell(value: widget.chunks[i].start),
          'end': PlutoCell(value: widget.chunks[i].end),
          'text': PlutoCell(value: widget.chunks[i].text),
          'note': PlutoCell(value: widget.chunks[i].hint ?? ''),
          'actions': PlutoCell(value: ''),
        },
      ),
  ];

  void _syncRows() {
    final stateManager = _stateManager;
    if (stateManager == null) return;
    if (_appliedStructure != _structureVersion) {
      stateManager.removeAllRows(notify: false);
      stateManager.appendRows(_rows);
      _appliedStructure = _structureVersion;
      return;
    }
    final rowsById = {
      for (final row in stateManager.refRows.originalList)
        row.cells['id']!.value as String: row,
    };
    for (var i = 0; i < widget.chunks.length; i++) {
      final chunk = widget.chunks[i];
      final row = rowsById[chunk.id];
      if (row == null) continue;
      _updateCell(stateManager, row, 'number', i + 1);
      _updateCell(stateManager, row, 'start', chunk.start);
      _updateCell(stateManager, row, 'end', chunk.end);
      _updateCell(stateManager, row, 'text', chunk.text);
      _updateCell(stateManager, row, 'note', chunk.hint ?? '');
    }
    stateManager.notifyListeners();
  }

  void _updateCell(
    PlutoGridStateManager stateManager,
    PlutoRow row,
    String field,
    dynamic value,
  ) {
    final cell = row.cells[field]!;
    if (cell.value != value) {
      stateManager.changeCellValue(
        cell,
        value,
        callOnChangedEvent: false,
        notify: false,
      );
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
            onPressed: () => widget.onTimeChanged(id, field, value - .1),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Expanded(
            child: TextFormField(
              key: ValueKey('$id-$field-$value'),
              initialValue: value.toStringAsFixed(2),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
              ),
              onFieldSubmitted: (text) {
                final changed = double.tryParse(text);
                if (changed != null) widget.onTimeChanged(id, field, changed);
              },
            ),
          ),
          IconButton(
            iconSize: 17,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            tooltip: 'Increase $title',
            onPressed: () => widget.onTimeChanged(id, field, value + .1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      );
    },
  );

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
        onPressed: () => widget.onAction(id, action),
        icon: Icon(icon),
      );
}
