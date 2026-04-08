import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/keyboard_shortcuts.dart';

class KeyboardShortcutsHelpDialog extends StatelessWidget {
  const KeyboardShortcutsHelpDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Keyboard shortcuts'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: OpenChatKeyboardShortcuts.helpSections
                .expand(
                  (KeyboardShortcutHelpSection section) => <Widget>[
                    Text(
                      section.title,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: context.openChatPalette.mutedText,
                          ),
                    ),
                    const SizedBox(height: 8),
                    ...section.entries.map(_ShortcutHelpRow.new),
                    const SizedBox(height: 16),
                  ],
                )
                .toList(growable: false),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _ShortcutHelpRow extends StatelessWidget {
  const _ShortcutHelpRow(this.entry);

  final KeyboardShortcutHelpEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: Text(entry.label)),
          const SizedBox(width: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: context.openChatPalette.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.openChatPalette.border),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                OpenChatKeyboardShortcuts.formatShortcutLabels(
                  entry.activators,
                ),
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
