import 'package:flutter/material.dart';

import '../models/prompt_template.dart';
import '../theme/app_theme.dart';

class PromptEditSheet extends StatefulWidget {
  const PromptEditSheet({super.key, this.initial, this.onSave});

  /// Pass an existing prompt to edit it; null to create a new one.
  final PromptTemplate? initial;

  /// Optional callback for embedding in a non-modal context (e.g. tests).
  /// When null and the widget is in a route, the route is popped with the result.
  final void Function(PromptTemplate)? onSave;

  @override
  State<PromptEditSheet> createState() => _PromptEditSheetState();
}

class _PromptEditSheetState extends State<PromptEditSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _systemPromptController;
  late final TextEditingController _modelController;

  bool _temperatureEnabled = false;
  double _temperature = 0.7;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final PromptTemplate? p = widget.initial;
    _nameController = TextEditingController(text: p?.name ?? '');
    _systemPromptController =
        TextEditingController(text: p?.systemPrompt ?? '');
    _modelController = TextEditingController(text: p?.model ?? '');
    if (p?.temperature != null) {
      _temperatureEnabled = true;
      _temperature = p!.temperature!;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _systemPromptController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final String? model = _modelController.text.trim().isNotEmpty
        ? _modelController.text.trim()
        : null;

    final DateTime now = DateTime.now();
    final PromptTemplate result = PromptTemplate(
      id: widget.initial?.id ?? 'prompt-${now.millisecondsSinceEpoch}',
      name: _nameController.text.trim(),
      systemPrompt: _systemPromptController.text.trim(),
      model: model,
      temperature: _temperatureEnabled ? _temperature : null,
      createdAt: widget.initial?.createdAt ?? now,
      updatedAt: now,
    );

    if (widget.onSave != null) {
      widget.onSave!(result);
    } else {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditing = widget.initial != null;
    final OpenChatPalette palette = context.openChatPalette;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Handle bar
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.mutedText.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
            child: Row(
              children: <Widget>[
                Text(
                  isEditing ? 'Edit prompt' : 'New prompt',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Cancel',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Form — scrollable to handle keyboard
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        hintText: 'e.g. Coding assistant',
                        border: OutlineInputBorder(),
                      ),
                      validator: (String? value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _systemPromptController,
                      minLines: 4,
                      maxLines: 10,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'System message',
                        hintText: 'You are a helpful assistant that…',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _modelController,
                      decoration: InputDecoration(
                        labelText: 'Model override (optional)',
                        hintText: 'Leave blank to use provider default',
                        helperText:
                            'If set, this model will be used for threads '
                            'started from this prompt.',
                        helperMaxLines: 2,
                        border: const OutlineInputBorder(),
                        suffixIcon: _modelController.text.isNotEmpty
                            ? IconButton(
                                tooltip: 'Clear',
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () =>
                                    setState(() => _modelController.clear()),
                              )
                            : null,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: <Widget>[
                        Checkbox(
                          value: _temperatureEnabled,
                          onChanged: (bool? v) => setState(
                              () => _temperatureEnabled = v ?? false),
                        ),
                        const SizedBox(width: 4),
                        const Text('Override temperature'),
                      ],
                    ),
                    if (_temperatureEnabled) ...<Widget>[
                      const SizedBox(height: 4),
                      Row(
                        children: <Widget>[
                          const SizedBox(width: 12),
                          Text(
                            _temperature.toStringAsFixed(1),
                            style: TextStyle(color: palette.accent),
                          ),
                          Expanded(
                            child: Slider(
                              value: _temperature,
                              min: 0.0,
                              max: 2.0,
                              divisions: 20,
                              label: _temperature.toStringAsFixed(1),
                              onChanged: (double v) =>
                                  setState(() => _temperature = v),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _save,
                      child: Text(
                          isEditing ? 'Save changes' : 'Create prompt'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
