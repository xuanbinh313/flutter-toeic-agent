import 'package:flutter/material.dart';

import 'models.dart';
import 'screens/exam_library.dart';
import 'screens/vocabulary_page.dart';
import 'services/local_database.dart';
import 'services/sync_service.dart';

class JunEduApp extends StatelessWidget {
  const JunEduApp({super.key});
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
  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _sync() async {
    final message = await SyncService.instance.sync();
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      ExamLibrary(exams: _exams, changed: () => setState(() {})),
      VocabularyPage(words: _words, changed: () => setState(() {})),
      _SettingsPage(onSync: _sync),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('JunEdu')),
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

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.onSync});
  final VoidCallback onSync;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Settings',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            leading: const Icon(Icons.cloud_sync_outlined),
            title: const Text('Cloud sync'),
            subtitle: const Text('Sync JunEdu records to Supabase.'),
            trailing: FilledButton(
              onPressed: onSync,
              child: const Text('Sync'),
            ),
          ),
        ),
        const Card(
          child: ListTile(
            leading: Icon(Icons.notifications_outlined),
            title: Text('Study reminders'),
            subtitle: Text('Manage reminders in the desktop application.'),
          ),
        ),
      ],
    ),
  );
}
