# JunEdu Flutter

Flutter desktop client for the Jun Edu SQLite study database.

## Local database

During development, the app opens `exams.db` from the current working directory.
For a packaged deployment, provide its location with:

```powershell
flutter run --dart-define=JUNEDU_DB_PATH=C:\data\exams.db
```

## Supabase production configuration

The `.env` file is bundled into every build, including release builds. Keep the
Supabase URL and publishable/anon key in it:

```dotenv
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your-publishable-key
SUPABASE_SCHEMA=public
```

`--dart-define` values still take precedence when you need to override a value
for a particular build:

```powershell
flutter build windows `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_KEY=your-publishable-key `
  --dart-define=SUPABASE_SCHEMA=public `
  --dart-define=JUNEDU_DB_PATH=C:\data\exams.db
```

Use a Supabase publishable/anon key only; never place a service-role key in a client application. Sign in through Supabase Auth before using the Sync button. Sync uploads dirty local rows and downloads the user-scoped Jun Edu tables.

## Validation

```powershell
flutter analyze
flutter test
```
