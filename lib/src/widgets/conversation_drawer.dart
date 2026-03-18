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
              const SizedBox(height: 8),
              Text(
                'Recent conversations',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.openChatPalette.mutedText,
                    ),
              ),
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
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const Key('drawer-new-chat-button'),
                onPressed: () async {
                  await Navigator.of(context).maybePop();
                  await onCreateThread();
                },
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('New chat'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('drawer-search-button'),
                onPressed: () async {
                  await Navigator.of(context).maybePop();
                  await onOpenSearch();
                },
                icon: const Icon(Icons.search_rounded),
                label: const Text('Search chats'),
              ),
              const SizedBox(height: 20),
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
              const SizedBox(height: 12),
              Text(
                'Transfer',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: context.openChatPalette.mutedText,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                    key: const Key('drawer-export-all-button'),
                    onPressed: threads.isEmpty ? null : onExportAllThreads,
                    icon: const Icon(Icons.library_books_outlined),
                    label: const Text('Export all'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('drawer-import-button'),
                    onPressed: onImportThreads,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('Import chats'),
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
