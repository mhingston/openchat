import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ChatEmptyState extends StatelessWidget {
  const ChatEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.detail,
    this.actionLabel,
    this.onAction,
    this.starterPrompts = const <String>[],
    this.onStarterPromptSelected,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? detail;
  final String? actionLabel;
  final VoidCallback? onAction;
  final List<String> starterPrompts;
  final ValueChanged<String>? onStarterPromptSelected;

  @override
  Widget build(BuildContext context) {
    final String? trimmedDetail = detail?.trim();
    final List<String> visibleStarterPrompts = starterPrompts
        .map((String prompt) => prompt.trim())
        .where((String prompt) => prompt.isNotEmpty)
        .toList(growable: false);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Container(
                    height: 88,
                    width: 88,
                    decoration: BoxDecoration(
                      color: context.openChatPalette.surfaceRaised,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: context.openChatPalette.border),
                    ),
                    child: Icon(
                      icon,
                      size: 40,
                      color: context.openChatPalette.accent,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontSize: 24,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.openChatPalette.mutedText,
                        ),
                  ),
                  if (trimmedDetail != null &&
                      trimmedDetail.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.openChatPalette.surface,
                        borderRadius: BorderRadius.circular(18),
                        border:
                            Border.all(color: context.openChatPalette.border),
                      ),
                      child: Text(
                        trimmedDetail,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: context.openChatPalette.danger,
                            ),
                      ),
                    ),
                  ],
                  if (visibleStarterPrompts.isNotEmpty &&
                      onStarterPromptSelected != null) ...<Widget>[
                    const SizedBox(height: 20),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: visibleStarterPrompts
                          .map(
                            (String prompt) => ActionChip(
                              label: Text(prompt),
                              onPressed: () => onStarterPromptSelected!(prompt),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                  if (actionLabel != null && onAction != null) ...<Widget>[
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
