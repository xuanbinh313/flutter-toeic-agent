import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'config.dart';
import 'screens/import_questions_agent_window.dart';
export 'app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.initialize();
  final controller = await WindowController.fromCurrentEngine();
  if (controller.arguments.isNotEmpty) {
    final arguments = jsonDecode(controller.arguments) as Map<String, dynamic>;
    if (arguments['window'] == 'import-questions-agent') {
      runApp(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff1a73e8),
            ),
          ),
          home: ImportQuestionsAgentWindow(
            examId: arguments['examId'] as String,
          ),
        ),
      );
      return;
    }
  }
  await windowManager.ensureInitialized();
  windowManager.waitUntilReadyToShow(const WindowOptions(), () async {
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(const JunEduApp());
}
