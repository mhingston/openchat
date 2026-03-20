import 'package:flutter/material.dart';

import '../models/chat_thread.dart';
import '../theme/app_theme.dart';
import 'conversation_list.dart';

class ConversationDrawer extends StatelessWidget {
  const ConversationDrawer({
    super.key,
    required this.threads,
    required this.selectedThreadId,
    required this.onCreateThread,
    required this.onOpenSearch,
    required this.onSelectThread,
    required this.onTogglePinnedThread,
    required this.onRenameThread,
    required this.onDuplicateThread,
    required this.onDeleteThread,
    required this.onExportAllThreads,
    required this.onImportThreads,
  });

  final List<ChatThread> threads;
  final String? selectedThreadId;
  final Future<void> Function() onCreateThread;
  final Future<void> Function() onOpenSearch;
  final Future<void> Function(String threadId) onSelectThread;
  final Future<void> Function(String threadId) onTogglePinnedThread;
  final Future<void> Function(String threadId) onRenameThread;
  final Future<void> Function(String threadId) onDuplicateThread;
  final Future<void> Function(String threadId) onDeleteThread;
  final Future<void> Function() onExportAllThreads;
  final Future<void> Function() onImportThreads;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('OpenChat', style: Theme.of(context).textTheme.titleLarge),
              if (threads
                  .any((ChatThread thread) => thread.isPinned)) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'Pinned conversations stay at the top.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.openChatPalette.mutedText,
                      ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Tooltip(
                    message: 'New chat',
                    child: FilledButton(
                      key: const Key('drawer-new-chat-button'),
                      onPressed: () async {
                        await Navigator.of(context).maybePop();
                        await onCreateThread();
                      },
                      child: const Icon(Icons.add_comment_outlined),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Search chats',
                    child: OutlinedButton(
                      key: const Key('drawer-search-button'),
                      onPressed: () async {
                        await Navigator.of(context).maybePop();
                        await onOpenSearch();
                      },
                      child: const Icon(Icons.search_rounded),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ConversationList(
                  threads: threads,
                  selectedThreadId: selectedThreadId,
                  onSelectThread: onSelectThread,
                  onTogglePinnedThread: onTogglePinnedThread,
                  onRenameThread: onRenameThread,
                  onDuplicateThread: onDuplicateThread,
                  onDeleteThread: onDeleteThread,
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Tooltip(
                    message: 'Export all',
                    child: OutlinedButton(
                      key: const Key('drawer-export-all-button'),
                      onPressed: threads.isEmpty ? null : onExportAllThreads,
                      child: const Icon(Icons.library_books_outlined),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Import chats',
                    child: OutlinedButton(
                      key: const Key('drawer-import-button'),
                      onPressed: onImportThreads,
                      child: const Icon(Icons.file_upload_outlined),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
