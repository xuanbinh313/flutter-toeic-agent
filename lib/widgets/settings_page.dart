import 'package:flutter/material.dart';

import '../services/reminder_settings_service.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.syncing,
    required this.syncFailed,
    required this.syncTargetRemote,
    required this.syncStatus,
    required this.lastSyncedAt,
    required this.authLoading,
    required this.userEmail,
    required this.onAuthenticate,
    required this.onLogout,
    required this.onSyncToRemote,
    required this.onSyncToLocal,
  });

  final bool syncing;
  final bool syncFailed;
  final bool? syncTargetRemote;
  final String? syncStatus;
  final DateTime? lastSyncedAt;
  final bool authLoading;
  final String? userEmail;
  final VoidCallback onAuthenticate;
  final VoidCallback onLogout;
  final VoidCallback onSyncToRemote;
  final VoidCallback onSyncToLocal;

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
            leading: Icon(
              userEmail == null
                  ? Icons.account_circle_outlined
                  : Icons.account_circle,
            ),
            title: Text(userEmail ?? 'Login / Register'),
            subtitle: Text(
              userEmail == null
                  ? 'Sign in to sync JunEdu records with Supabase.'
                  : 'Signed in to Supabase.',
            ),
            trailing: FilledButton.tonal(
              onPressed: authLoading
                  ? null
                  : userEmail == null
                  ? onAuthenticate
                  : onLogout,
              child: Text(userEmail == null ? 'Sign in' : 'Logout'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (syncStatus != null) ...[
          Card(
            child: ListTile(
              leading: _statusIcon(),
              title: Text(syncStatus!),
              subtitle: Text(
                syncing
                    ? syncTargetRemote == true
                          ? 'Syncing to remote'
                          : 'Syncing to local'
                    : syncFailed
                    ? 'Synchronization failed.'
                    : 'Synced at ${_formatTime(lastSyncedAt)}',
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _syncCard(
          targetRemote: true,
          title: 'Sync to Remote',
          description: 'Upload changed local records to Supabase.',
          onPressed: onSyncToRemote,
        ),
        const SizedBox(height: 12),
        _syncCard(
          targetRemote: false,
          title: 'Sync to Local',
          description: 'Download your Supabase records locally.',
          onPressed: onSyncToLocal,
        ),
        const _StudyRemindersCard(),
      ],
    ),
  );

  Widget _syncCard({
    required bool targetRemote,
    required String title,
    required String description,
    required VoidCallback onPressed,
  }) => Card(
    child: ListTile(
      leading: _actionIcon(targetRemote),
      title: Text(title),
      subtitle: Text(description),
      trailing: targetRemote
          ? FilledButton.icon(
              onPressed: syncing ? null : onPressed,
              icon: _buttonIcon(targetRemote),
              label: const Text('Sync'),
            )
          : FilledButton.tonalIcon(
              onPressed: syncing ? null : onPressed,
              icon: _buttonIcon(targetRemote),
              label: const Text('Sync'),
            ),
    ),
  );

  Widget _statusIcon() {
    if (syncing) return _progressIcon();
    return Icon(
      syncFailed ? Icons.error_outline : Icons.check_circle_outline,
      color: syncFailed ? Colors.red : Colors.green,
    );
  }

  Widget _actionIcon(bool targetRemote) {
    if (syncTargetRemote == targetRemote) return _statusIcon();
    return Icon(
      targetRemote
          ? Icons.cloud_upload_outlined
          : Icons.cloud_download_outlined,
    );
  }

  Widget _buttonIcon(bool targetRemote) {
    if (syncing && syncTargetRemote == targetRemote) return _progressIcon();
    if (!syncing && syncTargetRemote == targetRemote) {
      return Icon(syncFailed ? Icons.error_outline : Icons.check);
    }
    return const Icon(Icons.sync);
  }

  Widget _progressIcon() => const SizedBox(
    width: 16,
    height: 16,
    child: CircularProgressIndicator(strokeWidth: 2),
  );

  String _formatTime(DateTime? value) {
    if (value == null) return 'just now';
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/${value.year} '
        '$hour:$minute:$second';
  }
}

class _StudyRemindersCard extends StatefulWidget {
  const _StudyRemindersCard();

  @override
  State<_StudyRemindersCard> createState() => _StudyRemindersCardState();
}

class _StudyRemindersCardState extends State<_StudyRemindersCard> {
  final _minutes = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final minutes = await ReminderSettingsService.instance.loadMinutes();
    if (mounted) {
      setState(() {
        _minutes.text = '$minutes';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final minutes = int.tryParse(_minutes.text.trim());
    if (minutes == null || minutes < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one minute.')),
      );
      return;
    }
    setState(() => _saving = true);
    await ReminderSettingsService.instance.saveMinutes(minutes);
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Study reminder saved.')));
    }
  }

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.notifications_outlined),
      title: const Text('Study reminders'),
      subtitle: _loading
          ? const Text('Loading reminder preference…')
          : Text('Notify me after the configured study interval.'),
      trailing: SizedBox(
        width: 210,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _minutes,
                enabled: !_loading && !_saving,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Minutes',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _loading || _saving ? null : _save,
              child: Text(_saving ? 'Saving' : 'Save'),
            ),
          ],
        ),
      ),
    ),
  );
}
