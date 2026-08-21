import 'package:flutter/material.dart';

import '../services/exam_summary_service.dart';
import '../services/local_database.dart';

class ContextTagDialog extends StatefulWidget {
  const ContextTagDialog({
    super.key,
    required this.examId,
    required this.contextId,
  });

  final String examId;
  final String contextId;

  @override
  State<ContextTagDialog> createState() => _ContextTagDialogState();
}

class _ContextTagDialogState extends State<ContextTagDialog> {
  final _newTag = TextEditingController();
  final _tags = <String>[];
  final _selected = <String>{};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait([
      ExamSummaryService.instance.loadQuestionTags(widget.examId),
      LocalDatabase.instance.loadContextTags(widget.examId),
    ]);
    if (!mounted) return;
    setState(() {
      _tags
        ..clear()
        ..addAll(values[0] as List<String>);
      _selected
        ..clear()
        ..addAll(
          (values[1] as Map<String, Set<String>>)[widget.contextId] ?? {},
        );
      _loading = false;
    });
  }

  Future<void> _setTag(String tag, bool enabled) async {
    setState(() => _saving = true);
    await LocalDatabase.instance.setContextTag(widget.contextId, tag, enabled);
    if (!mounted) return;
    setState(() {
      enabled ? _selected.add(tag) : _selected.remove(tag);
      _saving = false;
    });
  }

  Future<void> _addTag() async {
    final tag = _newTag.text.trim();
    if (tag.isEmpty || _saving) return;
    _newTag.clear();
    if (!_tags.contains(tag)) {
      setState(() {
        _tags.add(tag);
        _tags.sort();
      });
    }
    await _setTag(tag, true);
  }

  @override
  void dispose() {
    _newTag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Tag / Untag'),
    content: SizedBox(
      width: 320,
      child: _loading
          ? const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _newTag,
                  autofocus: true,
                  onSubmitted: (_) => _addTag(),
                  decoration: InputDecoration(
                    labelText: 'New tag',
                    suffixIcon: IconButton(
                      tooltip: 'Add tag',
                      onPressed: _saving ? null : _addTag,
                      icon: const Icon(Icons.add),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_tags.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Add a tag to label this context.'),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final tag in _tags)
                          CheckboxListTile(
                            value: _selected.contains(tag),
                            onChanged: _saving
                                ? null
                                : (enabled) => _setTag(tag, enabled ?? false),
                            title: Text(tag),
                            activeColor: const Color(0xff1a73e8),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
