import 'package:flutter/material.dart';

import '../models/chat_thread.dart';
import '../theme/app_theme.dart';

class ConversationList extends StatelessWidget {
  const ConversationList({
    super.key,
    required this.threads,
    required this.selectedThreadId,
    required this.onSelectThread,
    required this.onTogglePinnedThread,
    required this.onRenameThread,
    required this.onDuplicateThread,
    required this.onDeleteThread,
  });

  final List<ChatThread> threads;
  final String? selectedThreadId;
  final Future<void> Function(String threadId) onSelectThread;
  final Future<void> Function(String threadId) onTogglePinnedThread;
  final Future<void> Function(String threadId) onRenameThread;
  final Future<void> Function(String threadId) onDuplicateThread;
  final Future<void> Function(String threadId) onDeleteThread;

  @override
  Widget build(BuildContext context) {
    if (threads.isEmpty) {
      return Center(
        child: Text(
          'No conversations yet.',
          style: TextStyle(color: context.openChatPalette.mutedText),
        ),
      );
    }

    return ListView.separated(
      itemCount: threads.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final ChatThread thread = threads[index];
        final bool isSelected = thread.id == selectedThreadId;

        return Material(
          color: isSelected
              ? context.openChatPalette.surfaceRaised
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: ListTile(
            onTap: () => onSelectThread(thread.id),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: isSelected
                    ? context.openChatPalette.accent
                    : context.openChatPalette.border,
              ),
            ),
            title: Row(
              children: <Widget>[
                if (thread.isPinned) ...<Widget>[
                  Icon(
                    Icons.push_pin_rounded,
                    size: 16,
                    color: context.openChatPalette.accent,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    thread.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            subtitle: Text(
              thread.previewText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.openChatPalette.mutedText),
            ),
            trailing: PopupMenuButton<_ConversationAction>(
              tooltip: 'Conversation actions',
              icon: const Icon(Icons.more_horiz),
              onSelected: (_ConversationAction action) {
                switch (action) {
                  case _ConversationAction.rename:
                    onRenameThread(thread.id);
                    return;
                  case _ConversationAction.pin:
                    onTogglePinnedThread(thread.id);
                    return;
                  case _ConversationAction.duplicate:
                    onDuplicateThread(thread.id);
                    return;
                  case _ConversationAction.delete:
                    onDeleteThread(thread.id);
                    return;
                }
              },
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<_ConversationAction>>[
                PopupMenuItem<_ConversationAction>(
                  value: _ConversationAction.pin,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      thread.isPinned
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_outlined,
                    ),
                    title: Text(thread.isPinned ? 'Unpin' : 'Pin'),
                  ),
                ),
                const PopupMenuItem<_ConversationAction>(
                  value: _ConversationAction.rename,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.drive_file_rename_outline),
                    title: Text('Rename'),
                  ),
                ),
                const PopupMenuItem<_ConversationAction>(
                  value: _ConversationAction.duplicate,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.copy_all_outlined),
                    title: Text('Duplicate'),
                  ),
                ),
                PopupMenuItem<_ConversationAction>(
                  value: _ConversationAction.delete,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.delete_outline,
                      color: context.openChatPalette.danger,
                    ),
                    title: Text(
                      'Delete',
                      style: TextStyle(
                        color: context.openChatPalette.danger,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _ConversationAction { pin, rename, duplicate, delete }
