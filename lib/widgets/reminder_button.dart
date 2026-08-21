import 'package:flutter/material.dart';

import '../services/background_app_service.dart';
import '../services/reminder_settings_service.dart';

class ReminderButton extends StatelessWidget {
  const ReminderButton({super.key, this.compact = false});

  final bool compact;

  Future<void> _schedule() async {
    final minutes = await ReminderSettingsService.instance.loadMinutes();
    await BackgroundAppService.instance.scheduleAndHide(
      Duration(minutes: minutes),
    );
  }

  @override
  Widget build(BuildContext context) => compact
      ? IconButton(
          onPressed: _schedule,
          tooltip: 'Notify me using the Study reminders setting',
          icon: const Icon(Icons.notifications_outlined),
        )
      : OutlinedButton.icon(
          onPressed: _schedule,
          icon: const Icon(Icons.notifications_outlined),
          label: const Text('Notify me'),
        );
}
