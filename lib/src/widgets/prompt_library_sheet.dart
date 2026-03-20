import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/chat_controller.dart';
import '../models/prompt_template.dart';
import '../theme/app_theme.dart';
import 'prompt_edit_sheet.dart';

class PromptLibrarySheet extends StatelessWidget {
  const PromptLibrarySheet({super.key});

  Future<void> _openEdit(
    BuildContext context,
    ChatController controller, {
    PromptTemplate? prompt,
  }) async {
    final PromptTemplate? result = await showModalBottomSheet<PromptTemplate>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PromptEditSheet(initial: prompt),
    );
    if (result != null) {
      await controller.savePrompt(result);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ChatController controller,
    PromptTemplate prompt,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Delete prompt?'),
        content: Text('Delete "${prompt.name}"? This cannot be undone.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: TextStyle(color: context.openChatPalette.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.deletePrompt(prompt.id);
    }
  }

  Future<void> _usePrompt(
    BuildContext context,
    ChatController controller,
    PromptTemplate prompt,
  ) async {
    Navigator.of(context).pop(); // close the library sheet
    await controller.createThreadFromPrompt(prompt);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatController>(
      builder: (BuildContext context, ChatController controller, _) {
        final List<PromptTemplate> prompts = controller.prompts;
        final OpenChatPalette palette = context.openChatPalette;

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (BuildContext context, ScrollController scrollController) {
            return Column(
              children: <Widget>[
                // Handle
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
                  padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.auto_awesome_outlined, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        'Prompt library',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      IconButton(
                        key: const Key('prompt-library-add-button'),
                        tooltip: 'New prompt',
                        icon: const Icon(Icons.add),
                        onPressed: () =>
                            _openEdit(context, controller),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // List / empty state
                Expanded(
                  child: prompts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.auto_awesome_outlined,
                                size: 48,
                                color: palette.mutedText.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No prompts yet',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(color: palette.mutedText),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Tap + to create your first prompt.',
                                style: TextStyle(color: palette.mutedText),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          itemCount: prompts.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 4),
                          itemBuilder: (BuildContext context, int index) {
                            final PromptTemplate prompt = prompts[index];
                            return Card(
                              margin: EdgeInsets.zero,
                              child: ListTile(
                                key: ValueKey<String>(prompt.id),
                                leading: const Icon(
                                    Icons.auto_awesome_outlined),
                                title: Text(
                                  prompt.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: prompt.systemPrompt.trim().isNotEmpty
                                    ? Text(
                                        prompt.systemPrompt,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: palette.mutedText),
                                      )
                                    : null,
                                trailing: PopupMenuButton<_PromptAction>(
                                  tooltip: 'Prompt actions',
                                  icon: const Icon(Icons.more_horiz),
                                  onSelected: (_PromptAction action) async {
                                    switch (action) {
                                      case _PromptAction.edit:
                                        await _openEdit(context, controller,
                                            prompt: prompt);
                                        return;
                                      case _PromptAction.delete:
                                        await _confirmDelete(
                                            context, controller, prompt);
                                        return;
                                    }
                                  },
                                  itemBuilder: (_) =>
                                      <PopupMenuEntry<_PromptAction>>[
                                    const PopupMenuItem<_PromptAction>(
                                      value: _PromptAction.edit,
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(
                                            Icons.drive_file_rename_outline),
                                        title: Text('Edit'),
                                      ),
                                    ),
                                    PopupMenuItem<_PromptAction>(
                                      value: _PromptAction.delete,
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(Icons.delete_outline,
                                            color: palette.danger),
                                        title: Text('Delete',
                                            style: TextStyle(
                                                color: palette.danger)),
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () =>
                                    _usePrompt(context, controller, prompt),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

enum _PromptAction { edit, delete }
