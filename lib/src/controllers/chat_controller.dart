import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/attachment.dart';
import '../models/chat_message.dart';
import '../models/chat_thread.dart';
import '../models/conversation_search_result.dart';
import '../models/provider_config.dart';
import '../models/web_search_result.dart';
import '../services/chat_store.dart';
import '../services/openai_compatible_client.dart';
import '../services/request_foreground_service.dart';
import '../services/web_page_browse_service.dart';
import '../services/web_search_service.dart';

class ChatController extends ChangeNotifier with WidgetsBindingObserver {
  ChatController(
      {required ChatStore chatStore,
      required OpenAiCompatibleClient apiClient,
      WebSearchService? webSearchService,
      WebPageBrowseService? webPageBrowseService})
      : _chatStore = chatStore,
        _apiClient = apiClient,
        _webSearchService = webSearchService ?? WebSearchService(),
        _webPageBrowseService =
            webPageBrowseService ?? WebPageBrowseService();

  final ChatStore _chatStore;
  final OpenAiCompatibleClient _apiClient;
  final WebSearchService _webSearchService;
  final WebPageBrowseService _webPageBrowseService;

  final List<ChatThread> _threads = <ChatThread>[];
  String? _selectedThreadId;
  bool _initialized = false;
  bool _isSending = false;
  String? _lastError;
  String? _searchStatus;
  int _nextLocalId = 0;

  List<ChatThread> get threads => List<ChatThread>.unmodifiable(_threads);
  bool get initialized => _initialized;
  bool get isSending => _isSending;
  String? get lastError => _lastError;
  String? get searchStatus => _searchStatus;
  bool get hasThreads => _threads.isNotEmpty;

  ChatThread? get currentThread {
    if (_selectedThreadId == null) {
      return null;
    }

    for (final ChatThread thread in _threads) {
      if (thread.id == _selectedThreadId) {
        return thread;
      }
    }

    return _threads.isEmpty ? null : _threads.first;
  }

  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    final List<ChatThread> storedThreads = await _chatStore.loadThreads();
    _threads
      ..clear()
      ..addAll(storedThreads);

    _sortThreads();
    _selectedThreadId = _threads.isEmpty ? null : _threads.first.id;
    _lastError = null;
    _initialized = true;
    notifyListeners();
  }

  Future<void> createThread() async {
    final ChatThread thread = _newThread();
    _threads.insert(0, thread);
    _selectedThreadId = thread.id;
    _lastError = null;
    await _persist();
    notifyListeners();
  }

  List<ConversationSearchResult> searchThreads(
    String query, {
    int maxResults = 50,
  }) {
    return _chatStore.searchThreads(
      threads: _threads,
      query: query,
      maxResults: maxResults,
    );
  }

  Future<int> importThreads({
    required List<ChatThread> threads,
    required bool replaceExisting,
  }) async {
    if (threads.isEmpty) {
      return 0;
    }

    final List<ChatThread> importedThreads =
        threads.map(_cloneImportedThread).toList(growable: false);
    if (replaceExisting) {
      _threads
        ..clear()
        ..addAll(importedThreads);
    } else {
      _threads.insertAll(0, importedThreads);
    }

    _lastError = null;
    _sortThreads();
    _selectedThreadId = _threads.isEmpty ? null : importedThreads.first.id;
    await _persist();
    notifyListeners();
    return importedThreads.length;
  }

  Future<void> selectThread(String threadId) async {
    if (!_threads.any((ChatThread thread) => thread.id == threadId)) {
      return;
    }

    _selectedThreadId = threadId;
    _lastError = null;
    notifyListeners();
  }

  Future<void> selectAdjacentThread(int offset) async {
    if (_threads.length < 2 || _selectedThreadId == null || offset == 0) {
      return;
    }

    final int currentIndex = _threads.indexWhere(
      (ChatThread thread) => thread.id == _selectedThreadId,
    );
    if (currentIndex == -1) {
      return;
    }

    final int targetIndex = (currentIndex + offset) % _threads.length;
    _selectedThreadId =
        _threads[targetIndex < 0 ? targetIndex + _threads.length : targetIndex]
            .id;
    _lastError = null;
    notifyListeners();
  }

  Future<void> renameThread(String threadId, String title) async {
    final int index = _threads.indexWhere(
      (ChatThread thread) => thread.id == threadId,
    );
    if (index == -1) {
      return;
    }

    final ChatThread thread = _threads[index];
    final String normalizedTitle = _normalizeThreadTitle(title);
    if (thread.title == normalizedTitle) {
      return;
    }

    _threads[index] = thread.copyWith(
      title: normalizedTitle,
      updatedAt: DateTime.now(),
    );
    _lastError = null;
    _sortThreads();
    await _persist();
    notifyListeners();
  }

  Future<void> duplicateThread(String threadId) async {
    final ChatThread? sourceThread = _threadById(threadId);
    if (sourceThread == null) {
      return;
    }

    final DateTime now = DateTime.now();
    final ChatThread duplicatedThread = sourceThread.copyWith(
      id: _newId('thread'),
      title: _duplicateThreadTitle(sourceThread.title),
      messages: sourceThread.messages
          .map(
            (ChatMessage message) => message.copyWith(
              id: _newId('message'),
              attachments: List<ChatAttachment>.from(message.attachments),
            ),
          )
          .toList(),
      createdAt: now,
      updatedAt: now,
      isPinned: false,
    );

    _threads.insert(0, duplicatedThread);
    _selectedThreadId = duplicatedThread.id;
    _lastError = null;
    _sortThreads();
    await _persist();
    notifyListeners();
  }

  Future<void> togglePinnedThread(String threadId) async {
    final int index = _threads.indexWhere(
      (ChatThread thread) => thread.id == threadId,
    );
    if (index == -1) {
      return;
    }

    final ChatThread thread = _threads[index];
    _threads[index] = thread.copyWith(
      isPinned: !thread.isPinned,
      updatedAt: DateTime.now(),
    );
    _lastError = null;
    _sortThreads();
    await _persist();
    notifyListeners();
  }

  Future<void> deleteThread(String threadId) async {
    final bool wasSelected = _selectedThreadId == threadId;
    final int index = _threads.indexWhere(
      (ChatThread thread) => thread.id == threadId,
    );
    if (index == -1) {
      return;
    }

    _threads.removeAt(index);
    _lastError = null;
    _sortThreads();
    if (_threads.isEmpty) {
      _selectedThreadId = null;
    } else if (wasSelected ||
        !_threads.any((ChatThread thread) => thread.id == _selectedThreadId)) {
      _selectedThreadId = _threads.first.id;
    }

    await _persist();
    notifyListeners();
  }

  Future<void> deleteMessage({
    required String threadId,
    required String messageId,
  }) async {
    final int threadIndex =
        _threads.indexWhere((ChatThread thread) => thread.id == threadId);
    if (threadIndex == -1) {
      return;
    }

    final ChatThread thread = _threads[threadIndex];
    final List<ChatMessage> updatedMessages = List<ChatMessage>.from(
      thread.messages,
    )..removeWhere((ChatMessage message) => message.id == messageId);

    if (updatedMessages.length == thread.messages.length) {
      return;
    }

    _threads[threadIndex] = thread.copyWith(
      messages: updatedMessages,
      updatedAt: DateTime.now(),
    );
    _lastError = null;
    _sortThreads();
    await _persist();
    notifyListeners();
  }

  Future<void> retryMessage({
    required String threadId,
    required String messageId,
    required ProviderConfig config,
  }) async {
    if (_isSending) {
      return;
    }

    final int threadIndex =
        _threads.indexWhere((ChatThread thread) => thread.id == threadId);
    if (threadIndex == -1) {
      return;
    }

    final ChatThread thread = _threads[threadIndex];
    final int messageIndex = thread.messages.indexWhere(
      (ChatMessage message) => message.id == messageId,
    );
    if (messageIndex == -1 || messageIndex != thread.messages.length - 1) {
      return;
    }

    final ChatMessage failedMessage = thread.messages[messageIndex];
    if (failedMessage.role != ChatRole.assistant ||
        !failedMessage.isError ||
        failedMessage.isStreaming) {
      return;
    }

    final List<ChatMessage> requestMessages = List<ChatMessage>.from(
      thread.messages.take(messageIndex),
    );
    final ChatMessage retryMessage = failedMessage.copyWith(
      text: '',
      isStreaming: true,
      isError: false,
    );

    _threads[threadIndex] = thread.copyWith(
      messages: <ChatMessage>[
        ...requestMessages,
        retryMessage,
      ],
      updatedAt: DateTime.now(),
    );
    _selectedThreadId = thread.id;
    _lastError = null;
    _isSending = true;
    notifyListeners();
    await _persist();

    try {
      await RequestForegroundService.start();
      await for (final ChatCompletionChunk chunk
          in _apiClient.streamChatCompletion(
        config: config,
        messages: requestMessages,
      )) {
        if (chunk.isDone) {
          _updateMessage(
            threadId: thread.id,
            messageId: retryMessage.id,
            updater: (ChatMessage message) {
              if (message.text.trim().isEmpty) {
                return message.copyWith(
                  text: 'No response received.',
                  isStreaming: false,
                  isError: true,
                );
              }
              return message.copyWith(isStreaming: false);
            },
          );
        } else {
          _updateMessage(
            threadId: thread.id,
            messageId: retryMessage.id,
            updater: (ChatMessage message) => message.copyWith(
              text: '${message.text}${chunk.delta}',
              isStreaming: true,
            ),
          );
        }
        notifyListeners();
      }
    } catch (error) {
      _lastError = error.toString();
      _updateMessage(
        threadId: thread.id,
        messageId: retryMessage.id,
        updater: (ChatMessage message) => message.copyWith(
          text:
              'Unable to reach the provider right now. Check settings and try again.\n\n${error.toString()}',
          isStreaming: false,
          isError: true,
        ),
      );
      notifyListeners();
    } finally {
      _isSending = false;
      unawaited(RequestForegroundService.stop());
      _sortThreads();
      await _persist();
      notifyListeners();
    }
  }

  Future<void> sendMessage({
    required String text,
    required List<ChatAttachment> attachments,
    required ProviderConfig config,
    bool useWebSearch = false,
  }) async {
    final String trimmedText = text.trim();
    if (_isSending || (trimmedText.isEmpty && attachments.isEmpty)) {
      return;
    }

    ChatThread thread = currentThread ?? _newThread();
    if (!_threads.any((ChatThread item) => item.id == thread.id)) {
      _threads.insert(0, thread);
      _selectedThreadId = thread.id;
    }

    final bool isFirstExchange = thread.messages.isEmpty;
    final DateTime now = DateTime.now();
    final ChatMessage userMessage = ChatMessage(
      id: _newId('message'),
      role: ChatRole.user,
      text: trimmedText,
      createdAt: now,
      attachments: List<ChatAttachment>.from(attachments),
      isStreaming: false,
      isError: false,
    );
    final ChatMessage assistantMessage = ChatMessage(
      id: _newId('message'),
      role: ChatRole.assistant,
      text: '',
      createdAt: now,
      attachments: const <ChatAttachment>[],
      isStreaming: true,
      isError: false,
    );

    final String nextTitle = thread.messages.isEmpty
        ? _deriveThreadTitle(trimmedText, attachments)
        : thread.title;
    thread = thread.copyWith(
      title: nextTitle,
      messages: <ChatMessage>[
        ...thread.messages,
        userMessage,
        assistantMessage,
      ],
      updatedAt: now,
    );

    await _submitThread(
      thread: thread,
      assistantMessage: assistantMessage,
      config: config,
      useWebSearch: useWebSearch,
      autoTitle: isFirstExchange,
    );
  }

  Future<bool> editUserMessageAndResubmit({
    required String threadId,
    required String messageId,
    required String text,
    required List<ChatAttachment> attachments,
    required ProviderConfig config,
    bool useWebSearch = false,
  }) async {
    if (_isSending) {
      return false;
    }

    final int threadIndex =
        _threads.indexWhere((ChatThread thread) => thread.id == threadId);
    if (threadIndex == -1) {
      return false;
    }

    final ChatThread thread = _threads[threadIndex];
    final int messageIndex = thread.messages.indexWhere(
      (ChatMessage message) => message.id == messageId,
    );
    if (messageIndex == -1) {
      return false;
    }

    final ChatMessage originalMessage = thread.messages[messageIndex];
    if (originalMessage.role != ChatRole.user || originalMessage.isStreaming) {
      return false;
    }

    final String trimmedText = text.trim();
    if (trimmedText.isEmpty && attachments.isEmpty) {
      return false;
    }

    final DateTime now = DateTime.now();
    final ChatMessage editedUserMessage = originalMessage.copyWith(
      text: trimmedText,
      attachments: List<ChatAttachment>.from(attachments),
    );
    final ChatMessage assistantMessage = ChatMessage(
      id: _newId('message'),
      role: ChatRole.assistant,
      text: '',
      createdAt: now,
      attachments: const <ChatAttachment>[],
      isStreaming: true,
      isError: false,
    );
    final ChatThread updatedThread = thread.copyWith(
      title: messageIndex == 0
          ? _deriveThreadTitle(trimmedText, attachments)
          : thread.title,
      messages: <ChatMessage>[
        ...thread.messages.take(messageIndex),
        editedUserMessage,
        assistantMessage,
      ],
      updatedAt: now,
    );

    await _submitThread(
      thread: updatedThread,
      assistantMessage: assistantMessage,
      config: config,
      useWebSearch: useWebSearch,
    );
    return true;
  }

  Future<bool> forkFromUserMessage({
    required String threadId,
    required String messageId,
    required ProviderConfig config,
  }) async {
    if (_isSending) {
      return false;
    }

    final ChatThread? sourceThread = _threadById(threadId);
    if (sourceThread == null) {
      return false;
    }

    final int messageIndex = sourceThread.messages.indexWhere(
      (ChatMessage message) => message.id == messageId,
    );
    if (messageIndex == -1) {
      return false;
    }

    final ChatMessage sourceMessage = sourceThread.messages[messageIndex];
    if (sourceMessage.role != ChatRole.user || sourceMessage.isStreaming) {
      return false;
    }

    final DateTime now = DateTime.now();
    final List<ChatMessage> forkedMessages = sourceThread.messages
        .take(messageIndex + 1)
        .map(_cloneForkedMessage)
        .toList(growable: false);
    final ChatMessage assistantMessage = ChatMessage(
      id: _newId('message'),
      role: ChatRole.assistant,
      text: '',
      createdAt: now,
      attachments: const <ChatAttachment>[],
      isStreaming: true,
      isError: false,
    );
    final ChatThread forkedThread = ChatThread(
      id: _newId('thread'),
      title: _forkThreadTitle(sourceThread.title),
      messages: <ChatMessage>[...forkedMessages, assistantMessage],
      createdAt: now,
      updatedAt: now,
      isPinned: false,
    );

    await _submitThread(
      thread: forkedThread,
      assistantMessage: assistantMessage,
      config: config,
    );
    return true;
  }

  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _apiClient.resetHttpClient();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _apiClient.dispose();
    _webSearchService.dispose();
    _webPageBrowseService.dispose();
    super.dispose();
  }

  ChatThread _newThread() {
    final DateTime now = DateTime.now();
    return ChatThread(
      id: _newId('thread'),
      title: 'New chat',
      messages: const <ChatMessage>[],
      createdAt: now,
      updatedAt: now,
      isPinned: false,
    );
  }

  String _deriveThreadTitle(String text, List<ChatAttachment> attachments) {
    final String candidate = text.trim();
    if (candidate.isNotEmpty) {
      final String condensed = candidate.replaceAll(RegExp(r'\s+'), ' ');
      return condensed.length > 36
          ? '${condensed.substring(0, 36)}…'
          : condensed;
    }
    if (attachments.isNotEmpty) {
      return attachments.first.name;
    }
    return 'New chat';
  }

  String _normalizeThreadTitle(String title) {
    final String normalized = title.trim().replaceAll(RegExp(r'\s+'), ' ');
    return normalized.isEmpty ? 'New chat' : normalized;
  }

  String _duplicateThreadTitle(String title) {
    return '${_normalizeThreadTitle(title)} (copy)';
  }

  String _forkThreadTitle(String title) {
    return '${_normalizeThreadTitle(title)} (fork)';
  }

  ChatThread _cloneImportedThread(ChatThread thread) {
    return thread.copyWith(
      id: _newId('thread'),
      title: _normalizeThreadTitle(thread.title),
      messages: thread.messages
          .map(
            (ChatMessage message) => message.copyWith(
              id: _newId('message'),
              attachments: message.attachments
                  .map(
                    (ChatAttachment attachment) => attachment.copyWith(
                      id: _newId('attachment'),
                    ),
                  )
                  .toList(growable: false),
              isStreaming: false,
            ),
          )
          .toList(growable: false),
      isPinned: thread.isPinned,
    );
  }

  ChatThread? _threadById(String threadId) {
    for (final ChatThread thread in _threads) {
      if (thread.id == threadId) {
        return thread;
      }
    }
    return null;
  }

  void _replaceThread(ChatThread updatedThread) {
    final int index = _threads.indexWhere(
      (ChatThread thread) => thread.id == updatedThread.id,
    );

    if (index == -1) {
      _threads.insert(0, updatedThread);
    } else {
      _threads[index] = updatedThread;
    }

    _selectedThreadId = updatedThread.id;
    _sortThreads();
  }

  ChatMessage _cloneForkedMessage(ChatMessage message) {
    return message.copyWith(
      id: _newId('message'),
      attachments: message.attachments
          .map(
            (ChatAttachment attachment) => attachment.copyWith(
              id: _newId('attachment'),
            ),
          )
          .toList(growable: false),
      isStreaming: false,
    );
  }

  void _updateMessage({
    required String threadId,
    required String messageId,
    required ChatMessage Function(ChatMessage message) updater,
  }) {
    final int threadIndex =
        _threads.indexWhere((ChatThread thread) => thread.id == threadId);
    if (threadIndex == -1) {
      return;
    }

    final ChatThread thread = _threads[threadIndex];
    final List<ChatMessage> updatedMessages =
        List<ChatMessage>.from(thread.messages);
    int messageIndex = -1;
    for (int index = updatedMessages.length - 1; index >= 0; index -= 1) {
      if (updatedMessages[index].id == messageId) {
        messageIndex = index;
        break;
      }
    }
    if (messageIndex == -1) {
      return;
    }

    updatedMessages[messageIndex] = updater(updatedMessages[messageIndex]);

    _threads[threadIndex] = thread.copyWith(
      messages: updatedMessages,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _persist() async {
    await _chatStore.saveThreads(_threads);
  }

  Future<void> _submitThread({
    required ChatThread thread,
    required ChatMessage assistantMessage,
    required ProviderConfig config,
    bool useWebSearch = false,
    bool autoTitle = false,
  }) async {
    _replaceThread(thread);
    _lastError = null;
    _isSending = true;
    notifyListeners();
    await _persist();

    try {
      final (List<ChatMessage> requestMessages, List<String> sources) =
          await _buildRequestMessages(
        thread: thread,
        assistantMessage: assistantMessage,
        useWebSearch: useWebSearch,
      );

      await RequestForegroundService.start();
      await for (final ChatCompletionChunk chunk
          in _apiClient.streamChatCompletion(
        config: config,
        messages: requestMessages,
      )) {
        if (chunk.isDone) {
          _updateMessage(
            threadId: thread.id,
            messageId: assistantMessage.id,
            updater: (ChatMessage message) {
              final String sanitizedText = _sanitizeAssistantOutput(message.text);
              if (sanitizedText.trim().isEmpty) {
                return message.copyWith(
                  text: 'No response received.',
                  isStreaming: false,
                  isError: true,
                );
              }
              return message.copyWith(
                text: sanitizedText,
                isStreaming: false,
                sources: sources,
              );
            },
          );
          if (autoTitle) {
            unawaited(_tryAutoGenerateTitle(
              threadId: thread.id,
              assistantMessageId: assistantMessage.id,
              config: config,
            ));
          }
        } else {
          _updateMessage(
            threadId: thread.id,
            messageId: assistantMessage.id,
            updater: (ChatMessage message) => message.copyWith(
              text: _sanitizeAssistantOutput('${message.text}${chunk.delta}'),
              isStreaming: true,
            ),
          );
        }
        notifyListeners();
      }
    } catch (error) {
      _lastError = error.toString();
      _updateMessage(
        threadId: thread.id,
        messageId: assistantMessage.id,
        updater: (ChatMessage message) => message.copyWith(
          text:
              'Unable to reach the provider right now. Check settings and try again.\n\n${error.toString()}',
          isStreaming: false,
          isError: true,
        ),
      );
      notifyListeners();
    } finally {
      _isSending = false;
      unawaited(RequestForegroundService.stop());
      _searchStatus = null;
      _sortThreads();
      await _persist();
      notifyListeners();
    }
  }

  Future<(List<ChatMessage>, List<String>)> _buildRequestMessages({
    required ChatThread thread,
    required ChatMessage assistantMessage,
    required bool useWebSearch,
  }) async {
    final List<ChatMessage> requestMessages = List<ChatMessage>.from(
      thread.messages,
    )..removeWhere((ChatMessage message) => message.id == assistantMessage.id);

    if (!useWebSearch) {
      return (requestMessages, const <String>[]);
    }

    ChatMessage? latestUserMessage;
    for (int index = requestMessages.length - 1; index >= 0; index -= 1) {
      final ChatMessage message = requestMessages[index];
      if (message.role == ChatRole.user) {
        latestUserMessage = message;
        break;
      }
    }
    if (latestUserMessage == null || latestUserMessage.text.trim().isEmpty) {
      return (requestMessages, const <String>[]);
    }

    _searchStatus = 'Searching the web…';
    notifyListeners();

    final String searchQuery = _buildSearchQuery(requestMessages);
    final List<WebSearchResult> results = await _webSearchService.search(
      searchQuery,
    );
    if (results.isEmpty) {
      _searchStatus = null;
      notifyListeners();
      return (requestMessages, const <String>[]);
    }

    _searchStatus = 'Browsing pages…';
    notifyListeners();

    final List<WebPageExcerpt> excerpts = await _webPageBrowseService.browse(
      results,
      query: searchQuery,
    );

    _searchStatus = null;
    notifyListeners();

    final List<String> sources = <String>[
      for (final WebSearchResult r in results) r.url,
      for (final WebPageExcerpt e in excerpts)
        if (!results.any((WebSearchResult r) => r.url == e.url)) e.url,
    ];

    final ChatMessage searchContextMessage = ChatMessage(
      id: _newId('message'),
      role: ChatRole.system,
      text: _webPageBrowseService.formatBrowseContext(
        searchQuery,
        results,
        excerpts,
      ),
      createdAt: DateTime.now(),
      attachments: const <ChatAttachment>[],
      isStreaming: false,
      isError: false,
    );

    return (<ChatMessage>[searchContextMessage, ...requestMessages], sources);
  }

  Future<void> _tryAutoGenerateTitle({
    required String threadId,
    required String assistantMessageId,
    required ProviderConfig config,
  }) async {
    final ChatThread? thread = _threadById(threadId);
    if (thread == null || thread.messages.length != 2) {
      return;
    }
    final ChatMessage userMsg = thread.messages[0];
    final ChatMessage assistantMsg = thread.messages[1];
    if (userMsg.role != ChatRole.user ||
        assistantMsg.role != ChatRole.assistant ||
        assistantMsg.isError ||
        assistantMsg.text.trim().isEmpty ||
        userMsg.text.trim().isEmpty) {
      return;
    }

    final String? generatedTitle = await _apiClient.generateTitle(
      config: config,
      userMessage: userMsg.text,
      assistantMessage: assistantMsg.text,
    );
    if (generatedTitle == null || generatedTitle.isEmpty) {
      return;
    }

    await renameThread(threadId, generatedTitle);
  }

  String _sanitizeAssistantOutput(String text) {
    String sanitized = text
        .replaceAll(
          RegExp(r'<think\b[^>]*>.*?</think>', caseSensitive: false, dotAll: true),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'^tool_call(?:s)?\([^)]*\):\s*\[(?:[^\]]|\](?!\s*\n\s*\n))*\]\s*',
            caseSensitive: false,
            dotAll: true,
            multiLine: true,
          ),
          '',
        )
        .replaceAll(RegExp(r'</?think\b[^>]*>', caseSensitive: false), ' ');

    sanitized = sanitized.replaceAll(
      RegExp(
        r'^\s*\{?\s*"url"\s*:\s*"https?://[^"]+"\s*\}?\s*$',
        caseSensitive: false,
        multiLine: true,
      ),
      '',
    );
    sanitized = sanitized.replaceAll(
      RegExp(
        r"^\s*(?:I(?:'ll| will| am going to|'m going to)\s+(?:fetch|browse|load|open|check|look up).*)$",
        caseSensitive: false,
        multiLine: true,
      ),
      '',
    );
    sanitized = sanitized.replaceAll(
      RegExp(
        r'^\s*(?:Fetching|Browsing|Loading|Opening)\b.*$',
        caseSensitive: false,
        multiLine: true,
      ),
      '',
    );
    sanitized = sanitized.replaceAll(
      RegExp(
        r'^\s*Let me\s+(?:fetch|browse|load|open|check|look up|extract)\b.*$',
        caseSensitive: false,
        multiLine: true,
      ),
      '',
    );
    sanitized = sanitized.replaceAll(
      RegExp(
        r'^\s*Based on the live .*embedded above,?\s*',
        caseSensitive: false,
        multiLine: true,
      ),
      '',
    );
    // Strip any trailing "Sources:" section the LLM appended — those are
    // rendered by the _SourcesFooter widget in the bubble instead.
    sanitized = sanitized.replaceAll(
      RegExp(
        r'\n\s*---\s*\n\s*\*?\*?Sources:?\*?\*?\s*\n[\s\S]*$',
        caseSensitive: false,
      ),
      '',
    );
    sanitized = sanitized.replaceAll(
      RegExp(
        r'\n\s*\*?\*?Sources:?\*?\*?\s*\n(?:\s*\[\d+\][^\n]*\n?)+\s*$',
        caseSensitive: false,
      ),
      '',
    );
    sanitized = sanitized
        .replaceAll(RegExp(r'^\s*\[\s*$', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*\]\s*$', multiLine: true), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return sanitized;
  }

  /// Builds a condensed search query from the last few conversation turns.
  /// Uses the latest user message as the primary query, but prefixes it with
  /// enough prior context so that follow-up questions like "what about next
  /// week?" are searchable without the AI conversation history.
  String _buildSearchQuery(List<ChatMessage> messages) {
    final List<ChatMessage> contextMessages = messages
        .where((ChatMessage m) =>
            m.role != ChatRole.system && m.text.trim().isNotEmpty)
        .toList();

    if (contextMessages.isEmpty) {
      return '';
    }

    final ChatMessage latestUser = contextMessages.lastWhere(
      (ChatMessage m) => m.role == ChatRole.user,
      orElse: () => contextMessages.last,
    );
    final String latestText = latestUser.text.trim();

    // If the latest message is already self-contained (long enough and has
    // clear nouns/entities), use it directly.
    final bool looksStandalone = latestText.split(' ').length >= 5 ||
        RegExp(r'[A-Z][a-z]').hasMatch(latestText);
    if (looksStandalone) {
      return latestText;
    }

    // Build a 2-turn context prefix: prior assistant snippet + current user.
    final List<ChatMessage> recent = contextMessages.length > 3
        ? contextMessages.sublist(contextMessages.length - 3)
        : contextMessages;

    final StringBuffer buffer = StringBuffer();
    for (final ChatMessage m in recent) {
      if (m == latestUser) continue;
      final String snippet = m.text.trim();
      final String short = snippet.length > 120
          ? '${snippet.substring(0, 120)}…'
          : snippet;
      buffer.write('${short.replaceAll('\n', ' ')} ');
    }
    buffer.write(latestText);
    return buffer.toString().trim();
  }

  void _sortThreads() {
    _threads.sort(
      (ChatThread a, ChatThread b) {
        if (a.isPinned != b.isPinned) {
          return a.isPinned ? -1 : 1;
        }
        return b.updatedAt.compareTo(a.updatedAt);
      },
    );
  }

  String _newId(String prefix) {
    final int suffix = _nextLocalId;
    _nextLocalId += 1;
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$suffix';
  }
}
