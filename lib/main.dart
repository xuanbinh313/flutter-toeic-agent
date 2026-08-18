import 'package:flutter/widgets.dart';

import 'app.dart';
import 'config.dart';
export 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.initialize();
  runApp(const JunEduApp());
}
