import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/external_audio_import_service.dart';
import '../services/local_database.dart';

class ExamDetailsForm extends StatefulWidget {
  const ExamDetailsForm({super.key, required this.exam, required this.onSaved});

  final Exam exam;
  final VoidCallback onSaved;

  @override
  State<ExamDetailsForm> createState() => _ExamDetailsFormState();
}

class _ExamDetailsFormState extends State<ExamDetailsForm> {
  late final _title = TextEditingController(text: widget.exam.title);
  late final _description = TextEditingController(
    text: widget.exam.description,
  );
  late final _audio = TextEditingController(
    text: widget.exam.audioName ?? widget.exam.audioPath ?? '',
  );
  late final _duration = TextEditingController(text: '${widget.exam.duration}');
  final _transcript = TextEditingController();
  late bool _published = widget.exam.published;
  String? _sourcePath;
  String? _analysisTaskId;
  String _progress = '';
  bool _saving = false;
  bool _working = false;
  late String _initialTitle = _title.text;
  late String _initialDescription = _description.text;
  late String _initialAudio = _audio.text;
  late String _initialDuration = _duration.text;
  late bool _initialPublished = _published;

  @override
  void initState() {
    super.initState();
    _title.addListener(_onChanged);
    _description.addListener(_onChanged);
    _audio.addListener(_onChanged);
    _duration.addListener(_onChanged);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _audio.dispose();
    _duration.dispose();
    _transcript.dispose();
    super.dispose();
  }

  bool get _isNew => widget.exam.id.isEmpty;

  bool get _hasChanges =>
      _title.text != _initialTitle ||
      _description.text != _initialDescription ||
      _audio.text != _initialAudio ||
      _duration.text != _initialDuration ||
      _published != _initialPublished;

  bool get _canSave =>
      !_saving &&
      !_working &&
      _title.text.trim().isNotEmpty &&
      (_isNew || _hasChanges);

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _markSaved() {
    _initialTitle = _title.text;
    _initialDescription = _description.text;
    _initialAudio = _audio.text;
    _initialDuration = _duration.text;
    _initialPublished = _published;
  }

  Future<void> _selectAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'wav', 'm4a', 'aac'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() {
      _sourcePath = path;
      _audio.text = path;
      _analysisTaskId = null;
      _transcript.clear();
      _progress = 'Audio selected. Analyze it to extract transcript text.';
    });
  }

  Future<void> _analyzeAudio() async {
    final path = _sourcePath ?? _audio.text.trim();
    if (path.isEmpty) {
      await _selectAudio();
    }
    final selected = _sourcePath ?? _audio.text.trim();
    if (selected.isEmpty) return;
    setState(() {
      _working = true;
      _progress = 'Preparing audio analysis...';
    });
    try {
      final analysis = await ExternalAudioImportService.instance.analyze(
        selected,
        _setProgress,
      );
      if (mounted) {
        setState(() {
          _analysisTaskId = analysis.taskId;
          _transcript.text = analysis.text;
          _progress =
              'Transcript extracted. Edit it, then import aligned audio.';
        });
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _importAudioAndTranscript() async {
    final path = _sourcePath ?? _audio.text.trim();
    if (_analysisTaskId == null || path.isEmpty) {
      _showError(
        'Analyze an audio file before importing aligned transcript chunks.',
      );
      return;
    }
    setState(() {
      _working = true;
      _progress = 'Starting aligned audio import...';
    });
    try {
      final imported = await ExternalAudioImportService.instance.importAligned(
        sourcePath: path,
        taskId: _analysisTaskId!,
        text: _transcript.text,
        progress: _setProgress,
      );
      _audio.text = imported.audioPath;
      _applyDraftToExam();
      await LocalDatabase.instance.updateExam(widget.exam);
      await LocalDatabase.instance.saveSrtChunks(
        widget.exam.id,
        imported.chunks,
      );
      _markSaved();
      if (mounted) {
        setState(
          () => _progress =
              'Imported audio and ${imported.chunks.length} transcript chunks.',
        );
      }
      widget.onSaved();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final title = _title.text.trim();
    if (title.isEmpty) {
      _showError('Title is required.');
      return;
    }
    setState(() => _saving = true);
    try {
      _applyDraftToExam();
      await LocalDatabase.instance.updateExam(widget.exam);
      _markSaved();
      widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Exam details saved.')));
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _setProgress(String message) {
    if (mounted) setState(() => _progress = message);
  }

  void _applyDraftToExam() {
    widget.exam.title = _title.text.trim();
    widget.exam.description = _description.text.trim();
    widget.exam.duration = int.tryParse(_duration.text) ?? 0;
    widget.exam.published = _published;
    final audio = _audio.text.trim();
    widget.exam.audioName = audio.isEmpty ? null : audio;
  }

  void _showError(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const Text(
        'Exam Details',
        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _title,
        decoration: const InputDecoration(
          labelText: 'Title',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _description,
        minLines: 3,
        maxLines: 5,
        decoration: const InputDecoration(
          labelText: 'Description',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _audio,
        readOnly: true,
        decoration: const InputDecoration(
          labelText: 'Audio file',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _working ? null : _selectAudio,
            icon: const Icon(Icons.upload_file),
            label: const Text('Upload Audio'),
          ),
          OutlinedButton.icon(
            onPressed: _working ? null : _analyzeAudio,
            icon: const Icon(Icons.graphic_eq),
            label: Text(_working ? 'Working...' : 'Analyze Audio'),
          ),
          FilledButton.icon(
            onPressed: _working || _analysisTaskId == null
                ? null
                : _importAudioAndTranscript,
            icon: const Icon(Icons.download_done),
            label: const Text('Import Audio + Transcript'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _transcript,
        minLines: 6,
        maxLines: 10,
        enabled: !_working,
        decoration: const InputDecoration(
          labelText: 'Extracted transcript',
          hintText:
              'Extracted transcript text appears here. Edit it before importing audio alignment.',
          border: OutlineInputBorder(),
        ),
      ),
      if (_progress.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _progress,
            style: const TextStyle(color: Color(0xff5f6368)),
          ),
        ),
      const SizedBox(height: 12),
      SizedBox(
        width: 180,
        child: TextField(
          controller: _duration,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Duration (minutes)',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      const SizedBox(height: 6),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Published'),
        value: _published,
        onChanged: (value) => setState(() => _published = value ?? false),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: _canSave ? _save : null,
          icon: const Icon(Icons.save),
          label: Text(_saving ? 'Saving...' : 'Save'),
        ),
      ),
    ],
  );
}
