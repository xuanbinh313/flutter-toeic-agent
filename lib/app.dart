import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'models.dart';
import 'screens/exam_library.dart';
import 'screens/vocabulary_page.dart';
import 'services/auth_service.dart';
import 'services/local_database.dart';
import 'services/sync_service.dart';
import 'widgets/settings_page.dart';

enum _MenuAction { authenticate, logout, syncToRemote, syncToLocal }

class JunEduApp extends StatefulWidget {
  const JunEduApp({super.key});

  @override
  State<JunEduApp> createState() => _JunEduAppState();
}

class _JunEduAppState extends State<JunEduApp>
    with WindowListener, TrayListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);
    _initializeTray();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    super.dispose();
  }

  Future<void> _initializeTray() async {
    if (!Platform.isWindows) return;
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
    await trayManager.setToolTip('JunEdu');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show_window', label: 'Open JunEdu'),
          MenuItem.separator(),
          MenuItem(key: 'exit_app', label: 'Exit JunEdu'),
        ],
      ),
    );
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onWindowClose() {
    // Keep the process alive so navigating back to the window resumes this
    // exact app session instead of starting over.
    windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() => _showWindow();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        _showWindow();
        return;
      case 'exit_app':
        windowManager.destroy();
        return;
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'JunEdu',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xfff7f9fc),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1a73e8)),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(fontSize: 12),
        bodyMedium: TextStyle(fontSize: 12),
        bodySmall: TextStyle(fontSize: 12),
        titleLarge: TextStyle(fontSize: 12),
        titleMedium: TextStyle(fontSize: 12),
        titleSmall: TextStyle(fontSize: 12),
        labelLarge: TextStyle(fontSize: 12),
        labelMedium: TextStyle(fontSize: 12),
        labelSmall: TextStyle(fontSize: 12),
      ),
    ),
    home: const Workspace(),
  );
}

class Workspace extends StatefulWidget {
  const Workspace({super.key});
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  int _section = 0;
  List<Exam> _exams = [];
  List<Vocab> _words = [];
  bool _syncing = false;
  bool _syncFailed = false;
  bool? _syncTargetRemote;
  String? _syncStatus;
  DateTime? _lastSyncedAt;
  bool _authLoading = false;
  String? _userEmail;
  @override
  void initState() {
    super.initState();
    _load();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      final email = await AuthService.instance.restoreSession();
      if (mounted) setState(() => _userEmail = email);
    } catch (_) {
      // A missing or expired saved session should not block local study.
    }
  }

  Future<void> _load() async {
    final values = await Future.wait([
      LocalDatabase.instance.loadExams(),
      LocalDatabase.instance.loadVocabulary(),
    ]);
    if (mounted) {
      setState(() {
        _exams = values[0] as List<Exam>;
        _words = values[1] as List<Vocab>;
      });
    }
  }

  Future<void> _syncToRemote() =>
      _sync(SyncService.instance.syncToRemote, true);

  Future<void> _syncToLocal() => _sync(SyncService.instance.syncToLocal, false);

  Future<void> _sync(
    Future<String> Function({SyncProgress? onProgress}) action,
    bool targetRemote,
  ) async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _syncFailed = false;
      _syncTargetRemote = targetRemote;
      _syncStatus = targetRemote
          ? 'Preparing remote sync...'
          : 'Preparing local sync...';
    });
    var message = 'Sync failed.';
    var succeeded = false;
    try {
      message = await action(
        onProgress: (status) {
          if (mounted) setState(() => _syncStatus = status);
        },
      );
      await _load();
      succeeded = true;
    } catch (error) {
      message = 'Sync failed: $error';
      if (mounted) setState(() => _syncFailed = true);
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
          _syncStatus = message;
          if (succeeded) _lastSyncedAt = DateTime.now();
        });
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _showAuth() async {
    final result = await showDialog<AuthResult>(
      context: context,
      builder: (_) => const _AuthDialog(),
    );
    if (result == null || !mounted) return;
    if (result.email != null) setState(() => _userEmail = result.email);
    if (result.message.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  Future<void> _logout() async {
    if (_authLoading) return;
    setState(() => _authLoading = true);
    String message = 'Logged out.';
    try {
      await AuthService.instance.signOut();
      _userEmail = null;
    } catch (error) {
      message = 'Logout failed: $error';
    } finally {
      if (mounted) setState(() => _authLoading = false);
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _onMenuAction(_MenuAction action) {
    switch (action) {
      case _MenuAction.authenticate:
        _showAuth();
        return;
      case _MenuAction.logout:
        _logout();
        return;
      case _MenuAction.syncToRemote:
        _syncToRemote();
        return;
      case _MenuAction.syncToLocal:
        _syncToLocal();
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      ExamLibrary(exams: _exams, changed: _load),
      VocabularyPage(words: _words, changed: () => setState(() {})),
      SettingsPage(
        syncing: _syncing,
        syncFailed: _syncFailed,
        syncTargetRemote: _syncTargetRemote,
        syncStatus: _syncStatus,
        lastSyncedAt: _lastSyncedAt,
        authLoading: _authLoading,
        userEmail: _userEmail,
        onAuthenticate: _showAuth,
        onLogout: _logout,
        onSyncToRemote: _syncToRemote,
        onSyncToLocal: _syncToLocal,
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('JunEdu'),
        actions: [
          PopupMenuButton<_MenuAction>(
            tooltip: 'Menu',
            onSelected: _onMenuAction,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _userEmail == null
                    ? _MenuAction.authenticate
                    : _MenuAction.logout,
                child: Text(_userEmail == null ? 'Login / Register' : 'Logout'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: _MenuAction.syncToRemote,
                child: Text('Sync to Remote'),
              ),
              const PopupMenuItem(
                value: _MenuAction.syncToLocal,
                child: Text('Sync to Local'),
              ),
            ],
          ),
        ],
      ),
      body: pages[_section],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _section,
        onDestinationSelected: (value) => setState(() => _section = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Exams',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Vocabulary',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _AuthDialog extends StatefulWidget {
  const _AuthDialog();

  @override
  State<_AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<_AuthDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLogin = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (!_isLogin && password != _confirmPasswordController.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = _isLogin
          ? await AuthService.instance.signIn(email, password)
          : await AuthService.instance.signUp(email, password);
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(Object error) {
    final message = '$error';
    final normalized = message.toLowerCase();
    if (normalized.contains('invalid login credentials')) {
      return 'Invalid email or password.';
    }
    if (normalized.contains('not confirmed')) {
      return 'Please verify your email before logging in.';
    }
    if (normalized.contains('already registered') ||
        normalized.contains('already exists')) {
      return 'That email is already registered.';
    }
    return message;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_isLogin ? 'Login' : 'Create account'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isLogin
                ? 'Sign in to manage your exams.'
                : 'Create your JunEdu account.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _emailController,
            enabled: !_loading,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            enabled: !_loading,
            obscureText: true,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          if (!_isLogin) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _confirmPasswordController,
              enabled: !_loading,
              obscureText: true,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: 'Confirm password'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _loading
            ? null
            : () => setState(() {
                _isLogin = !_isLogin;
                _error = null;
              }),
        child: Text(_isLogin ? 'Create an account' : 'Back to login'),
      ),
      TextButton(
        onPressed: _loading ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _loading ? null : _submit,
        child: _loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(_isLogin ? 'Login' : 'Register'),
      ),
    ],
  );
}
