import 'package:shared_preferences/shared_preferences.dart';

class ReminderSettingsService {
  ReminderSettingsService._();

  static final instance = ReminderSettingsService._();
  static const _minutesKey = 'study_reminder_minutes';
  static const defaultMinutes = 10;

  Future<int> loadMinutes() async {
    final preferences = await SharedPreferences.getInstance();
    final minutes = preferences.getInt(_minutesKey) ?? defaultMinutes;
    return minutes < 1 ? defaultMinutes : minutes;
  }

  Future<void> saveMinutes(int minutes) async {
    if (minutes < 1) throw ArgumentError.value(minutes, 'minutes');
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_minutesKey, minutes);
  }
}
