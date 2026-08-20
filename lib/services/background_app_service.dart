import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class BackgroundAppService with TrayListener {
  BackgroundAppService._();

  static final instance = BackgroundAppService._();

  Timer? _timer;
  bool _trayActive = false;
  bool _backgroundMode = false;

  bool get isBackgroundMode => _backgroundMode;

  Future<void> scheduleAndHide(Duration delay) async {
    await _enableTray();
    _timer?.cancel();
    _timer = Timer(delay, _restoreWindow);
    _backgroundMode = true;
    await windowManager.setPreventClose(true);
    await windowManager.hide();
  }

  Future<void> _enableTray() async {
    if (_trayActive || !Platform.isWindows) return;
    final iconData = await rootBundle.load(
      'windows/runner/resources/app_icon.ico',
    );
    final directory = await getTemporaryDirectory();
    final icon = File(
      '${directory.path}${Platform.pathSeparator}junedu_tray.ico',
    );
    await icon.writeAsBytes(
      iconData.buffer.asUint8List(
        iconData.offsetInBytes,
        iconData.lengthInBytes,
      ),
      flush: true,
    );
    await trayManager.setIcon(icon.path);
    await trayManager.setToolTip('JunEdu reminder is active');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'open_window', label: 'Open JunEdu'),
          MenuItem.separator(),
          MenuItem(key: 'exit_app', label: 'Exit JunEdu'),
        ],
      ),
    );
    trayManager.addListener(this);
    _trayActive = true;
  }

  Future<void> _restoreWindow() async {
    _timer?.cancel();
    _timer = null;
    _backgroundMode = false;
    if (_trayActive) {
      await trayManager.destroy();
      trayManager.removeListener(this);
      _trayActive = false;
    }
    await windowManager.setPreventClose(false);
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _exitApplication() async {
    _timer?.cancel();
    _backgroundMode = false;
    if (_trayActive) {
      await trayManager.destroy();
      trayManager.removeListener(this);
      _trayActive = false;
    }
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onTrayIconMouseDown() => _restoreWindow();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open_window':
        _restoreWindow();
        return;
      case 'exit_app':
        _exitApplication();
        return;
    }
  }
}
