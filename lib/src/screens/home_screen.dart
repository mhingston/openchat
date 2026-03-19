import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../controllers/chat_controller.dart';
import '../controllers/settings_controller.dart';
import '../models/attachment.dart';
import '../models/chat_message.dart';
import '../models/chat_thread.dart';
import '../models/conversation_search_result.dart';
import '../models/provider_config.dart';
import '../services/chat_export_service.dart';
import '../services/voice_input_service.dart';
import '../theme/app_theme.dart';
import '../utils/keyboard_shortcuts.dart';
import '../widgets/chat_composer.dart';
import '../widgets/chat_empty_state.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/conversation_drawer.dart';
import '../widgets/conversation_search_sheet.dart';
import '../widgets/open_chat_header.dart';
import '../widgets/settings_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ChatExportService _chatExportService = ChatExportService();
  final ScrollController _messagesScrollController = ScrollController();
  String? _editingThreadId;
  String? _editingMessageId;
  String? _editingDraftText;
  List<ChatAttachment> _editingBaseAttachments = const <ChatAttachment>[];
  int _composerDraftVersion = 0;

  @override
  void dispose() {
    _messagesScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ChatController chatController = context.watch<ChatController>();
    final SettingsController settingsController =
        context.watch<SettingsController>();
    final ProviderConfig providerConfig = settingsController.providerConfig;
    final ChatThread? currentThread = chatController.currentThread;
    final bool showProviderBanner = !settingsController.hasConfiguredProvider &&
        currentThread != null &&
        currentThread.messages.isNotEmpty;

    // Auto-scroll to the bottom while streaming a response or when switching
    // to a thread for the first time during a send.
    if (chatController.isSending && currentThread != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_messagesScrollController.hasClients &&
            _messagesScrollController.position.maxScrollExtent > 0) {
          _messagesScrollController.animateTo(
            _messagesScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
          );
        }
      });
    }

    final Widget child = Scaffold(
      key: _scaffoldKey,
      drawer: ConversationDrawer(
        threads: chatController.threads,
        selectedThreadId: chatController.currentThread?.id,
        onCreateThread: () => _createThread(context),
        onOpenSearch: () => _openSearchSheet(context),
        onSelectThread: (String threadId) => _selectThread(
          context,
          threadId,
        ),
        onTogglePinnedThread: (String threadId) => _togglePinnedThread(
          context,
          threadId,
        ),
        onRenameThread: (String threadId) async {
          await _renameThread(context, threadId);
        },
        onDuplicateThread: (String threadId) async {
          await _duplicateThread(context, threadId);
        },
        onDeleteThread: (String threadId) async {
          await _deleteThread(context, threadId);
        },
        onExportAllThreads: () async {
          await _exportAllThreads(context);
        },
        onImportThreads: () async {
          await _importThreads(context);
        },
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              context.openChatPalette.background,
              context.openChatPalette.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: <Widget>[
              OpenChatHeader(
                title: 'OpenChat',
                subtitle: providerConfig.model.trim(),
                onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
                onExportPressed: currentThread == null
                    ? null
                    : () => _exportThread(context, currentThread.id),
                onSettingsPressed: () => _openSettingsSheet(context),
              ),
              if (showProviderBanner)
                _ProviderSetupBanner(
                  onOpenSettings: () => _openSettingsSheet(context),
                ),
              Expanded(
                child: _buildConversationPane(
                  context,
                  chatController: chatController,
                  settingsController: settingsController,
                ),
              ),
              if (chatController.searchStatus != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Row(
                    children: <Widget>[
                      SizedBox.square(
                        dimension: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        chatController.searchStatus!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.5),
                            ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  chatController.searchStatus != null ? 4 : 0,
                  16,
                  16,
                ),
                child: ChatComposer(
                  enabled: providerConfig.isValidForChat &&
                      !chatController.isSending,
                  busy:
                      providerConfig.isValidForChat && chatController.isSending,
                  draftText: _editingDraftText,
                  draftVersion: _composerDraftVersion,
                  editingLabel:
                      _editingMessageId == null ? null : 'Editing message',
                  onCancelEdit:
                      _editingMessageId == null ? null : _clearEditingDraft,
                  voiceService: context.watch<VoiceInputService>(),
                  onSend: (String text, List<ChatAttachment> attachments,
                      bool useWebSearch) async {
                    if (!providerConfig.isValidForChat) {
                      return false;
                    }

                    final ChatController controller =
                        context.read<ChatController>();
                    if (_editingMessageId != null && _editingThreadId != null) {
                      final bool edited =
                          await controller.editUserMessageAndResubmit(
                        threadId: _editingThreadId!,
                        messageId: _editingMessageId!,
                        text: text,
                        attachments: <ChatAttachment>[
                          ..._editingBaseAttachments,
                          ...attachments,
                        ],
                        config: providerConfig,
                        useWebSearch: useWebSearch,
                      );
                      if (!edited) {
                        return false;
                      }
                    } else {
                      await controller.sendMessage(
                        text: text,
                        attachments: attachments,
                        config: providerConfig,
                        useWebSearch: useWebSearch,
                      );
                    }
                    if (!mounted) {
                      return true;
                    }

                    final String? lastError = chatController.lastError;
                    if (lastError != null && lastError.isNotEmpty) {
                      _showSnackBar(lastError);
                    }
                    return true;
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!OpenChatKeyboardShortcuts.isDesktopOrWeb) {
      return child;
    }

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        OpenChatKeyboardShortcuts.primaryActivator(LogicalKeyboardKey.keyN):
            const NewChatIntent(),
        OpenChatKeyboardShortcuts.primaryActivator(LogicalKeyboardKey.keyK):
            const NewChatIntent(),
        OpenChatKeyboardShortcuts.primaryActivator(LogicalKeyboardKey.comma):
            const OpenSettingsIntent(),
        OpenChatKeyboardShortcuts.primaryActivator(LogicalKeyboardKey.keyF):
            const FocusConversationSearchIntent(),
        OpenChatKeyboardShortcuts.primaryActivator(
          LogicalKeyboardKey.bracketLeft,
        ): const SelectPreviousConversationIntent(),
        OpenChatKeyboardShortcuts.primaryActivator(
          LogicalKeyboardKey.bracketRight,
        ): const SelectNextConversationIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          NewChatIntent: CallbackAction<NewChatIntent>(
            onInvoke: (NewChatIntent intent) {
              unawaited(_createThread(context));
              return null;
            },
          ),
          OpenSettingsIntent: CallbackAction<OpenSettingsIntent>(
            onInvoke: (OpenSettingsIntent intent) {
              unawaited(_openSettingsSheet(context));
              return null;
            },
          ),
          FocusConversationSearchIntent:
              CallbackAction<FocusConversationSearchIntent>(
            onInvoke: (FocusConversationSearchIntent intent) {
              unawaited(_openSearchSheet(context));
              return null;
            },
          ),
          SelectPreviousConversationIntent:
              CallbackAction<SelectPreviousConversationIntent>(
            onInvoke: (SelectPreviousConversationIntent intent) {
              unawaited(
                context.read<ChatController>().selectAdjacentThread(-1),
              );
              return null;
            },
          ),
          SelectNextConversationIntent:
              CallbackAction<SelectNextConversationIntent>(
            onInvoke: (SelectNextConversationIntent intent) {
              unawaited(
                context.read<ChatController>().selectAdjacentThread(1),
              );
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }

  Future<void> _createThread(BuildContext context) async {
    await context.read<ChatController>().createThread();
    if (!mounted) {
      return;
    }
    _closeDrawerIfOpen();
  }

  Future<void> _selectThread(BuildContext context, String threadId) async {
    await context.read<ChatController>().selectThread(threadId);
    if (!mounted) {
      return;
    }
    _closeDrawerIfOpen();
    // Jump to the bottom of the newly selected conversation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_messagesScrollController.hasClients) {
        _messagesScrollController.jumpTo(
          _messagesScrollController.position.maxScrollExtent,
        );
      }
    });
  }

  Future<void> _togglePinnedThread(
      BuildContext context, String threadId) async {
    final ChatController chatController = context.read<ChatController>();
    final ChatThread? thread = _findThread(chatController, threadId);
    if (thread == null) {
      return;
    }

    await chatController.togglePinnedThread(threadId);
    if (!mounted) {
      return;
    }

    _showSnackBar(
      thread.isPinned ? 'Conversation unpinned.' : 'Conversation pinned.',
    );
  }

  Future<void> _openSettingsSheet(BuildContext context) async {
    final SettingsController settingsController =
        context.read<SettingsController>();

    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return SettingsSheet(
          providerConfig: settingsController.providerConfig,
          themeMode: settingsController.themeMode,
          onSave: (ProviderConfig providerConfig, ThemeMode themeMode) async {
            await settingsController.saveConfiguration(
              providerConfig: providerConfig,
              themeMode: themeMode,
            );
          },
        );
      },
    );

    if (!mounted || saved != true) {
      return;
    }

    final String selectedModel =
        settingsController.providerConfig.model.trim().isEmpty
            ? 'your selected model'
            : settingsController.providerConfig.model.trim();
    _showSnackBar('Settings saved. Ready to chat with $selectedModel.');
  }

  Future<void> _openSearchSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.88,
          child: ConversationSearchSheet(
            onSearch: context.read<ChatController>().searchThreads,
            onResultSelected: (ConversationSearchResult result) {
              return _selectThread(context, result.threadId);
            },
          ),
        );
      },
    );
  }

  Widget _buildConversationPane(
    BuildContext context, {
    required ChatController chatController,
    required SettingsController settingsController,
  }) {
    final ChatThread? currentThread = chatController.currentThread;
    final String? lastError = _normalizedError(chatController.lastError);

    if (!settingsController.hasConfiguredProvider &&
        (currentThread == null || currentThread.messages.isEmpty)) {
      return ChatEmptyState(
        icon: Icons.settings_suggest_outlined,
        title: 'Set up a provider to start',
        message: currentThread == null
            ? 'Choose a provider, add your API details, fetch a model, and save your setup.'
            : 'Finish provider setup before sending your first message.',
        detail: lastError,
        actionLabel: 'Open settings',
        onAction: () => _openSettingsSheet(context),
      );
    }

    if (currentThread == null) {
      return ChatEmptyState(
        icon: Icons.forum_outlined,
        title: 'No conversations yet',
        message:
            'Create a new chat to start keeping separate conversation history.',
        detail: lastError,
        actionLabel: 'New chat',
        onAction: () async {
          await context.read<ChatController>().createThread();
        },
      );
    }

    if (currentThread.messages.isEmpty) {
      return ChatEmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: currentThread.title,
        message: 'This conversation is empty. Send a message to get started.',
        detail: lastError,
      );
    }

    return Column(
      children: <Widget>[
        if (lastError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: _ErrorBanner(
              message: lastError,
              onDismiss: chatController.clearError,
            ),
          ),
        Expanded(
          child: ListView.separated(
            controller: _messagesScrollController,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            itemCount: currentThread.messages.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (BuildContext context, int index) {
              final ChatMessage message = currentThread.messages[index];
              final bool canRetry =
                  index == currentThread.messages.length - 1 &&
                      message.role == ChatRole.assistant &&
                      message.isError &&
                      !message.isStreaming;
              return ChatMessageBubble(
                message: message,
                onCopy: message.text.trim().isEmpty
                    ? null
                    : () => _copyMessage(message.text),
                onRetry: canRetry
                    ? () => _retryMessage(
                          context,
                          threadId: currentThread.id,
                          messageId: message.id,
                        )
                    : null,
                onDelete: () => _deleteMessage(
                  context,
                  threadId: currentThread.id,
                  messageId: message.id,
                ),
                onEdit: message.role == ChatRole.user
                    ? () => _startEditingMessage(
                          threadId: currentThread.id,
                          message: message,
                        )
                    : null,
                onFork: message.role == ChatRole.user
                    ? () => _forkFromMessage(
                          context,
                          threadId: currentThread.id,
                          messageId: message.id,
                        )
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _renameThread(BuildContext context, String threadId) async {
    final ChatController chatController = context.read<ChatController>();
    final ChatThread? thread = _findThread(chatController, threadId);
    if (thread == null) {
      return;
    }

    final TextEditingController titleController = TextEditingController(
      text: thread.title,
    );
    final String? updatedTitle = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Rename conversation'),
          content: TextField(
            controller: titleController,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (String value) {
              Navigator.of(dialogContext).pop(value);
            },
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'Conversation name',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(titleController.text);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    titleController.dispose();

    if (updatedTitle == null) {
      return;
    }

    final String normalizedTitle =
        updatedTitle.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalizedTitle.isEmpty
        ? thread.title == 'New chat'
        : normalizedTitle == thread.title) {
      return;
    }

    await chatController.renameThread(threadId, updatedTitle);
    if (!mounted) {
      return;
    }

    _closeDrawerIfOpen();
    _showSnackBar('Conversation renamed.');
  }

  Future<void> _duplicateThread(BuildContext context, String threadId) async {
    final ChatController chatController = context.read<ChatController>();
    final ChatThread? thread = _findThread(chatController, threadId);
    if (thread == null) {
      return;
    }

    await chatController.duplicateThread(threadId);
    if (!mounted) {
      return;
    }

    _closeDrawerIfOpen();
    _showSnackBar('Duplicated "${thread.title}".');
  }

  Future<void> _deleteThread(BuildContext context, String threadId) async {
    final ChatController chatController = context.read<ChatController>();
    final ChatThread? thread = _findThread(chatController, threadId);
    if (thread == null) {
      return;
    }

    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: const Text('Delete conversation?'),
              content: Text(
                'Delete "${thread.title}"? This removes its messages from this device.',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    await chatController.deleteThread(threadId);
    if (!mounted) {
      return;
    }

    _closeDrawerIfOpen();
    _showSnackBar('Conversation deleted.');
  }

  Future<void> _retryMessage(
    BuildContext context, {
    required String threadId,
    required String messageId,
  }) async {
    final ChatController chatController = context.read<ChatController>();
    final ProviderConfig providerConfig =
        context.read<SettingsController>().providerConfig;

    await chatController.retryMessage(
      threadId: threadId,
      messageId: messageId,
      config: providerConfig,
    );
    if (!mounted) {
      return;
    }

    final String? lastError = _normalizedError(chatController.lastError);
    if (lastError != null) {
      _showSnackBar(lastError);
    }
  }

  Future<void> _deleteMessage(
    BuildContext context, {
    required String threadId,
    required String messageId,
  }) async {
    final ChatController chatController = context.read<ChatController>();
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: const Text('Delete message?'),
              content: const Text(
                'Delete this message from the current conversation?',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    await chatController.deleteMessage(
      threadId: threadId,
      messageId: messageId,
    );
    if (!mounted) {
      return;
    }

    _showSnackBar('Message deleted.');
  }

  void _startEditingMessage({
    required String threadId,
    required ChatMessage message,
  }) {
    setState(() {
      _editingThreadId = threadId;
      _editingMessageId = message.id;
      _editingDraftText = message.text;
      _editingBaseAttachments = List<ChatAttachment>.from(message.attachments);
      _composerDraftVersion += 1;
    });
  }

  void _clearEditingDraft() {
    if (_editingMessageId == null &&
        _editingDraftText == null &&
        _editingBaseAttachments.isEmpty) {
      return;
    }

    setState(() {
      _editingThreadId = null;
      _editingMessageId = null;
      _editingDraftText = null;
      _editingBaseAttachments = const <ChatAttachment>[];
      _composerDraftVersion += 1;
    });
  }

  Future<void> _forkFromMessage(
    BuildContext context, {
    required String threadId,
    required String messageId,
  }) async {
    final ChatController chatController = context.read<ChatController>();
    final ProviderConfig providerConfig =
        context.read<SettingsController>().providerConfig;

    if (!providerConfig.isValidForChat) {
      await _openSettingsSheet(context);
      return;
    }

    final bool forked = await chatController.forkFromUserMessage(
      threadId: threadId,
      messageId: messageId,
      config: providerConfig,
    );
    if (!mounted || !forked) {
      return;
    }

    _clearEditingDraft();
    _showSnackBar('Conversation forked from this message.');
  }

  Future<void> _copyMessage(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    _showSnackBar('Message copied.');
  }

  Future<void> _exportThread(BuildContext context, String threadId) async {
    final ChatController chatController = context.read<ChatController>();
    final ChatThread? thread = _findThread(chatController, threadId);
    if (thread == null) {
      return;
    }

    final ExportFormat? format = await _showExportFormatSheet(
      context,
      title: 'Export current chat',
    );
    if (format == null) {
      return;
    }

    try {
      final String? location = await _chatExportService.exportThread(
        thread: thread,
        format: format,
      );
      if (!mounted || location == null) {
        return;
      }
      _closeDrawerIfOpen();
      _showSnackBar(
        _exportSuccessMessage(
          format,
          allThreads: false,
          location: location,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar('Export failed: $error');
    }
  }

  Future<void> _exportAllThreads(BuildContext context) async {
    final ChatController chatController = context.read<ChatController>();
    if (chatController.threads.isEmpty) {
      _showSnackBar('Create a chat first, then export it from the drawer.');
      return;
    }

    final ExportFormat? format = await _showExportFormatSheet(
      context,
      title: 'Export all chats',
    );
    if (format == null) {
      return;
    }

    try {
      final String? location = await _chatExportService.exportThreads(
        threads: chatController.threads,
        format: format,
      );
      if (!mounted || location == null) {
        return;
      }
      _closeDrawerIfOpen();
      _showSnackBar(
        _exportSuccessMessage(
          format,
          allThreads: true,
          location: location,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar('Export failed: $error');
    }
  }

  Future<void> _importThreads(BuildContext context) async {
    final ChatController chatController = context.read<ChatController>();
    final ImportResult importResult = await _chatExportService.importThreads();
    if (!mounted || importResult.isCancelled) {
      return;
    }

    if (importResult.isError) {
      _showSnackBar(importResult.errorMessage!);
      return;
    }

    final List<ChatThread> importedThreads = importResult.threads!;
    final _ImportMode? mode = await _showImportModeDialog(
      this.context,
      importedThreads.length,
    );
    if (mode == null) {
      return;
    }

    final int importedCount = await chatController.importThreads(
      threads: importedThreads,
      replaceExisting: mode == _ImportMode.replace,
    );
    if (!mounted) {
      return;
    }

    _closeDrawerIfOpen();
    _showSnackBar(
      mode == _ImportMode.replace
          ? 'Replaced your local chats with $importedCount imported conversation(s).'
          : 'Imported $importedCount conversation(s) into your library.',
    );
  }

  Future<ExportFormat?> _showExportFormatSheet(
    BuildContext context, {
    required String title,
  }) {
    return showModalBottomSheet<ExportFormat>(
      context: context,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(title: Text(title)),
              ListTile(
                leading: const Icon(Icons.data_object_outlined),
                title: const Text('JSON'),
                subtitle: const Text('Best for importing back into OpenChat.'),
                onTap: () => Navigator.of(sheetContext).pop(ExportFormat.json),
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Markdown'),
                subtitle:
                    const Text('Readable transcript for sharing or notes.'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(ExportFormat.markdown),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<_ImportMode?> _showImportModeDialog(
    BuildContext context,
    int threadCount,
  ) {
    return showDialog<_ImportMode>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Import conversations'),
          content: Text(
            'Found $threadCount conversation(s). Do you want to merge them with your current chats or replace everything on this device?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_ImportMode.merge),
              child: const Text('Merge'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_ImportMode.replace),
              child: const Text('Replace'),
            ),
          ],
        );
      },
    );
  }

  ChatThread? _findThread(ChatController chatController, String threadId) {
    for (final ChatThread thread in chatController.threads) {
      if (thread.id == threadId) {
        return thread;
      }
    }
    return null;
  }

  String? _normalizedError(String? error) {
    final String? trimmed = error?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  void _closeDrawerIfOpen() {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _exportSuccessMessage(
    ExportFormat format, {
    required bool allThreads,
    required String location,
  }) {
    final String target = allThreads ? 'All chats' : 'Current chat';
    final String formatLabel =
        format == ExportFormat.json ? 'JSON' : 'Markdown';
    final String fileName = location.split(RegExp(r'[\\/]')).last;
    return '$target exported as $formatLabel to $fileName.';
  }
}

enum _ImportMode { merge, replace }

class _ProviderSetupBanner extends StatelessWidget {
  const _ProviderSetupBanner({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.info_outline,
                color: context.openChatPalette.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Provider setup is incomplete',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add a base URL, model, and API key if your provider needs one.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.openChatPalette.mutedText,
                          ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: onOpenSettings,
                      child: const Text('Open settings'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.error_outline,
              color: context.openChatPalette.danger,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.openChatPalette.danger,
                    ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onDismiss,
              tooltip: 'Dismiss error',
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}
