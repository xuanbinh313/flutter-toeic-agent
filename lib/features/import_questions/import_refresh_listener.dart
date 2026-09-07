import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';

/// Reloads exam data when returning from the separate import window.
class ImportRefreshListener with WindowListener {
  ImportRefreshListener(this.onRefresh) {
    windowManager.addListener(this);
    _windowsSubscription = onWindowsChanged.listen((_) => onRefresh());
  }

  final Future<void> Function() onRefresh;
  late final StreamSubscription<void> _windowsSubscription;

  @override
  void onWindowFocus() => unawaited(onRefresh());

  void dispose() {
    windowManager.removeListener(this);
    unawaited(_windowsSubscription.cancel());
  }
}
