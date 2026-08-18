# Flutter Project Rules

- Keep every Dart source file at 500 lines or fewer.
- When a widget, screen, or feature approaches the limit, extract cohesive child widgets, models, or helpers into separate files.
- Prefer feature-oriented folders under `lib/` and keep `main.dart` limited to app startup.
- Run `dart format`, `flutter analyze`, and `flutter test` after structural refactors.
