import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/chat_controller.dart';
import '../models/chat_thread.dart';
import '../theme/app_theme.dart';
import 'conversation_list.dart';
import 'prompt_library_sheet.dart';

class ConversationDrawer extends StatefulWidget {
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
  State<ConversationDrawer> createState() => _ConversationDrawerState();
}

class _ConversationDrawerState extends State<ConversationDrawer> {
  /// null = show all threads; a folder id = show only that folder's threads.
  String? _selectedFolderId;

  Future<void> _openPromptLibrary(BuildContext context) async {
    await Navigator.of(context).maybePop();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const PromptLibrarySheet(),
    );
  }

  Future<void> _showCreateFolderDialog(
    BuildContext context,
    ChatController controller,
  ) async {
    final TextEditingController nameController = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name'),
          onSubmitted: (String v) => Navigator.pop(ctx, v),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, nameController.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || name.trim().isEmpty) return;
    controller.createFolder(name.trim());
  }

  Future<void> _showRenameFolderDialog(
    BuildContext context,
    ChatController controller,
    String folderId,
    String currentName,
  ) async {
    final TextEditingController nameController =
        TextEditingController(text: currentName);
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Rename folder'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name'),
          onSubmitted: (String v) => Navigator.pop(ctx, v),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, nameController.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || name.trim().isEmpty) return;
    await controller.renameFolder(folderId, name.trim());
  }

  Future<void> _confirmDeleteFolder(
    BuildContext context,
    ChatController controller,
    String folderId,
    String folderName,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Delete folder?'),
        content: Text(
          'Delete "$folderName"? Conversations inside will not be deleted.',
        ),
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
    if (confirmed != true) return;
    if (_selectedFolderId == folderId) {
      setState(() => _selectedFolderId = null);
    }
    await controller.deleteFolder(folderId);
  }

  @override
  Widget build(BuildContext context) {
    final ChatController controller = context.watch<ChatController>();
    final Map<String, String> folders = controller.folders;

    final List<ChatThread> visibleThreads = _selectedFolderId == null
        ? widget.threads
        : widget.threads
            .where((ChatThread t) => t.folderId == _selectedFolderId)
            .toList();

    return Drawer(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('OpenChat', style: Theme.of(context).textTheme.titleLarge),
              if (widget.threads
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
                        await widget.onCreateThread();
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
                        await widget.onOpenSearch();
                      },
                      child: const Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Prompt library',
                    child: OutlinedButton(
                      key: const Key('drawer-prompt-library-button'),
                      onPressed: () => _openPromptLibrary(context),
                      child: const Icon(Icons.auto_awesome_outlined),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // --- Folders section ---
              _FoldersSection(
                folders: folders,
                threads: widget.threads,
                selectedFolderId: _selectedFolderId,
                onSelectFolder: (String? id) =>
                    setState(() => _selectedFolderId = id),
                onCreateFolder: () =>
                    _showCreateFolderDialog(context, controller),
                onRenameFolder: (String id, String name) =>
                    _showRenameFolderDialog(context, controller, id, name),
                onDeleteFolder: (String id, String name) =>
                    _confirmDeleteFolder(context, controller, id, name),
              ),
              const SizedBox(height: 8),

              Expanded(
                child: ConversationList(
                  threads: visibleThreads,
                  selectedThreadId: widget.selectedThreadId,
                  onSelectThread: widget.onSelectThread,
                  onTogglePinnedThread: widget.onTogglePinnedThread,
                  onRenameThread: widget.onRenameThread,
                  onDuplicateThread: widget.onDuplicateThread,
                  onDeleteThread: widget.onDeleteThread,
                  folders: folders,
                  onMoveToFolder: (String threadId, String? folderId) =>
                      controller.moveThreadToFolder(threadId, folderId),
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
                      onPressed: widget.threads.isEmpty
                          ? null
                          : widget.onExportAllThreads,
                      child: const Icon(Icons.library_books_outlined),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Import chats',
                    child: OutlinedButton(
                      key: const Key('drawer-import-button'),
                      onPressed: widget.onImportThreads,
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

/// Collapsible folders section rendered above the thread list.
class _FoldersSection extends StatefulWidget {
  const _FoldersSection({
    required this.folders,
    required this.threads,
    required this.selectedFolderId,
    required this.onSelectFolder,
    required this.onCreateFolder,
    required this.onRenameFolder,
    required this.onDeleteFolder,
  });

  final Map<String, String> folders;
  final List<ChatThread> threads;
  final String? selectedFolderId;
  final void Function(String? folderId) onSelectFolder;
  final VoidCallback onCreateFolder;
  final void Function(String folderId, String name) onRenameFolder;
  final void Function(String folderId, String name) onDeleteFolder;

  @override
  State<_FoldersSection> createState() => _FoldersSectionState();
}

class _FoldersSectionState extends State<_FoldersSection> {
  bool _expanded = true;

  int _threadCount(String folderId) =>
      widget.threads.where((ChatThread t) => t.folderId == folderId).length;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: <Widget>[
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: context.openChatPalette.mutedText,
                ),
                const SizedBox(width: 4),
                Text(
                  'Folders',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: context.openChatPalette.mutedText,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(width: 6),
                if (widget.selectedFolderId != null)
                  GestureDetector(
                    onTap: () => widget.onSelectFolder(null),
                    child: Tooltip(
                      message: 'Show all chats',
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: context.openChatPalette.accent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_expanded) ...<Widget>[
          if (widget.folders.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
              child: Text(
                'No folders yet.',
                style: TextStyle(
                  fontSize: 12,
                  color: context.openChatPalette.mutedText,
                ),
              ),
            ),
          for (final MapEntry<String, String> entry in widget.folders.entries)
            _FolderRow(
              folderId: entry.key,
              folderName: entry.value,
              threadCount: _threadCount(entry.key),
              isSelected: widget.selectedFolderId == entry.key,
              onTap: () => widget.onSelectFolder(
                widget.selectedFolderId == entry.key ? null : entry.key,
              ),
              onRename: () => widget.onRenameFolder(entry.key, entry.value),
              onDelete: () => widget.onDeleteFolder(entry.key, entry.value),
            ),
          TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: widget.onCreateFolder,
            icon: Icon(
              Icons.create_new_folder_outlined,
              size: 16,
              color: context.openChatPalette.mutedText,
            ),
            label: Text(
              'New folder',
              style: TextStyle(
                fontSize: 12,
                color: context.openChatPalette.mutedText,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Divider(height: 1),
        ],
      ],
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.folderId,
    required this.folderName,
    required this.threadCount,
    required this.isSelected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final String folderId;
  final String folderName;
  final int threadCount;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? context.openChatPalette.accent.withValues(alpha: 0.1)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.folder_outlined,
                size: 16,
                color: isSelected
                    ? context.openChatPalette.accent
                    : context.openChatPalette.mutedText,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  folderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: isSelected
                        ? context.openChatPalette.accent
                        : null,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (threadCount > 0) ...<Widget>[
                const SizedBox(width: 4),
                Text(
                  '$threadCount',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.openChatPalette.mutedText,
                  ),
                ),
              ],
              PopupMenuButton<_FolderAction>(
                padding: EdgeInsets.zero,
                iconSize: 16,
                tooltip: 'Folder actions',
                icon: Icon(
                  Icons.more_horiz,
                  size: 16,
                  color: context.openChatPalette.mutedText,
                ),
                onSelected: (_FolderAction action) {
                  switch (action) {
                    case _FolderAction.rename:
                      onRename();
                      return;
                    case _FolderAction.delete:
                      onDelete();
                      return;
                  }
                },
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<_FolderAction>>[
                  const PopupMenuItem<_FolderAction>(
                    value: _FolderAction.rename,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.drive_file_rename_outline),
                      title: Text('Rename'),
                    ),
                  ),
                  PopupMenuItem<_FolderAction>(
                    value: _FolderAction.delete,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.delete_outline,
                        color: context.openChatPalette.danger,
                      ),
                      title: Text(
                        'Delete',
                        style: TextStyle(color: context.openChatPalette.danger),
                      ),
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

enum _FolderAction { rename, delete }
