import 'package:flutter/material.dart';
import 'capture.dart';

class TaskEditor extends StatefulWidget {
  const TaskEditor({super.key, this.initial});
  final CaptureDraft? initial;
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  final capture = TextEditingController();
  final relay = TextEditingController(text: relayAddress);
  final token = TextEditingController();
  String? relayFeedback;

  void connectRelay() {
    try {
      configureRelay(relay.text, token.text);
      token.clear();
      setState(() => relayFeedback = 'Relay configured for this session.');
    } on FormatException catch (problem) {
      setState(() => relayFeedback = problem.message);
    }
  }

  final fields = {
    for (final k in [
      'title',
      'subject',
      'dueDate',
      'dueTime',
      'estimateMinutes',
      'notes',
      'subtasks',
      'afterCompletion',
    ])
      k: TextEditingController(),
  };
  bool reviewing = false, busy = false, highPriority = false;
  String? status, error;
  @override
  void initState() {
    super.initState();
    if (widget.initial != null) fill(widget.initial!);
  }

  void fill(CaptureDraft draft) {
    final data = draft.toJson();
    for (final e in fields.entries) {
      final val = data[e.key];
      e.value.text = val is List ? val.join('\n') : val?.toString() ?? '';
    }
    reviewing = true;
    highPriority = draft.priority == 'high';
  }

  Future<void> parse(bool cloud) async {
    final text = capture.text.trim();
    if (text.isEmpty) {
      setState(() => error = 'Write the homework first.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final now = DateTime.now();
    var draft = basicCapture(text, now);
    var message = 'Local draft';
    if (cloud) {
      try {
        draft = await cloudCapture(text, now);
        message = 'Gemini draft';
      } catch (_) {
        message = 'Gemini was unavailable. Review the local draft.';
      }
    }
    if (mounted)
      setState(() {
        fill(draft);
        status = message;
        busy = false;
      });
  }

  void save() {
    final values = <String, dynamic>{
      'version': 1,
      'priority': highPriority ? 'high' : 'normal',
    };
    for (final e in fields.entries) {
      final text = e.value.text.trim();
      if (e.key == 'subtasks' || e.key == 'afterCompletion') {
        values[e.key] = text
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList();
      } else if (e.key == 'estimateMinutes') {
        values[e.key] = text.isEmpty ? null : int.tryParse(text) ?? text;
      } else {
        values[e.key] = (text.isEmpty && e.key != 'title' && e.key != 'notes')
            ? null
            : text;
      }
    }
    try {
      Navigator.pop(context, CaptureDraft.fromJson(values));
    } on FormatException catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  void dispose() {
    capture.dispose();
    relay.dispose();
    token.dispose();
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget field(
    String name,
    String label, {
    int lines = 1,
    String? hint,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: fields[name],
      minLines: lines,
      maxLines: lines == 1 ? 1 : 6,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        alignLabelWithHint: true,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.initial != null
            ? 'Edit homework'
            : reviewing
            ? 'Review homework'
            : 'Capture',
      ),
    ),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (!reviewing) ...[
                TextField(
                  controller: capture,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'What do you need to do?',
                    hintText: 'Maths homework due Friday, about an hour…',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                if (cloudConfigured) ...[
                  const Text(
                    'Parse with Gemini sends this capture to your configured relay and Google.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: busy ? null : () => parse(true),
                    icon: const Icon(Icons.notes),
                    label: Text(busy ? 'Parsing…' : 'Parse with Gemini'),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => parse(false),
                    child: const Text('Use local capture'),
                  ),
                ] else
                  FilledButton(
                    onPressed: () => parse(false),
                    child: const Text('Review local draft'),
                  ),
                ExpansionTile(
                  title: const Text('Gemini relay settings'),
                  children: [
                    TextField(
                      controller: relay,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'Relay address', hintText: 'https://…'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: token,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(labelText: 'Relay access token'),
                    ),
                    TextButton(onPressed: busy ? null : connectRelay, child: const Text('Use for this session')),
                    if (relayFeedback != null) Text(relayFeedback!),
                  ],
                ),
              ] else ...[
                if (status != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      status!,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                field('title', 'Homework'),
                field('subject', 'Subject'),
                field('dueDate', 'Due date', hint: 'YYYY-MM-DD'),
                field('dueTime', 'Due time', hint: 'HH:mm'),
                field(
                  'estimateMinutes',
                  'Estimated minutes',
                  keyboard: TextInputType.number,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('High priority'),
                  value: highPriority,
                  onChanged: (v) => setState(() => highPriority = v),
                ),
                field('notes', 'Notes', lines: 2),
                field('subtasks', 'Steps · one per line', lines: 2),
                field(
                  'afterCompletion',
                  'Remind me after finishing · one per line',
                  lines: 2,
                ),
                FilledButton.icon(
                  onPressed: save,
                  icon: const Icon(Icons.check),
                  label: const Text('Save homework'),
                ),
                if (widget.initial == null)
                  TextButton(
                    onPressed: () => setState(() {
                      reviewing = false;
                      error = null;
                    }),
                    child: const Text('Back to capture'),
                  ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
