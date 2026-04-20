import 'package:flutter/material.dart';

class RecordingTitleEditorPage extends StatefulWidget {
  const RecordingTitleEditorPage({
    super.key,
    required this.pageTitle,
    required this.initialTitle,
    this.confirmLabel = 'Save',
    this.showUseDefault = false,
  });

  final String pageTitle;
  final String initialTitle;
  final String confirmLabel;
  final bool showUseDefault;

  @override
  State<RecordingTitleEditorPage> createState() =>
      _RecordingTitleEditorPageState();
}

class _RecordingTitleEditorPageState extends State<RecordingTitleEditorPage> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pageTitle),
        actions: [
          TextButton(
            onPressed: _submit,
            child: Text(widget.confirmLabel),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose a clear title so this lecture is easy to find later.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16.0),
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: false,
                maxLength: 80,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Lecture title',
                  hintText: 'Enter recording name',
                  border: OutlineInputBorder(),
                ),
              ),
              if (widget.showUseDefault) ...[
                const SizedBox(height: 8.0),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(''),
                  child: const Text('Use default name'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
