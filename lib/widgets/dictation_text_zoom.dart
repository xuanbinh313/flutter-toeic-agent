import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DictationTextZoom extends StatefulWidget {
  const DictationTextZoom({super.key, required this.builder});

  final Widget Function(BuildContext context, Widget controls) builder;

  @override
  State<DictationTextZoom> createState() => _DictationTextZoomState();
}

class _DictationTextZoomState extends State<DictationTextZoom> {
  double _scale = 1;

  void _change(double amount) =>
      setState(() => _scale = (_scale + amount).clamp(.8, 1.6));

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.equal, control: true): _ZoomInIntent(),
      SingleActivator(LogicalKeyboardKey.equal, control: true, shift: true):
          _ZoomInIntent(),
      SingleActivator(LogicalKeyboardKey.add, control: true): _ZoomInIntent(),
      SingleActivator(LogicalKeyboardKey.minus, control: true):
          _ZoomOutIntent(),
      SingleActivator(LogicalKeyboardKey.digit0, control: true):
          _ZoomResetIntent(),
    },
    child: Actions(
      actions: {
        _ZoomInIntent: CallbackAction<_ZoomInIntent>(
          onInvoke: (_) => _change(.1),
        ),
        _ZoomOutIntent: CallbackAction<_ZoomOutIntent>(
          onInvoke: (_) => _change(-.1),
        ),
        _ZoomResetIntent: CallbackAction<_ZoomResetIntent>(
          onInvoke: (_) => setState(() => _scale = 1),
        ),
      },
      child: Focus(
        autofocus: true,
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(_scale)),
            child: widget.builder(context, _controls()),
          ),
        ),
      ),
    ),
  );

  Widget _controls() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        onPressed: _scale <= .8 ? null : () => _change(-.1),
        tooltip: 'Zoom out (Ctrl+-)',
        icon: const Icon(Icons.zoom_out),
      ),
      IconButton(
        onPressed: _scale >= 1.6 ? null : () => _change(.1),
        tooltip: 'Zoom in (Ctrl++)',
        icon: const Icon(Icons.zoom_in),
      ),
      IconButton(
        onPressed: _scale == 1 ? null : () => setState(() => _scale = 1),
        tooltip: 'Reset zoom (Ctrl+0)',
        icon: const Icon(Icons.restart_alt),
      ),
    ],
  );
}

class _ZoomInIntent extends Intent {
  const _ZoomInIntent();
}

class _ZoomOutIntent extends Intent {
  const _ZoomOutIntent();
}

class _ZoomResetIntent extends Intent {
  const _ZoomResetIntent();
}
