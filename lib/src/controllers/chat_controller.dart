import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/attachment.dart';
import '../models/chat_message.dart';
import '../models/chat_thread.dart';
import '../models/conversation_search_result.dart';
import '../models/prompt_template.dart';
import '../models/provider_config.dart';
import '../models/web_search_result.dart';
import '../services/chat_store.dart';
import '../services/openai_compatible_client.dart';
import '../services/prompt_template_store.dart';
import '../services/request_foreground_service.dart';
import '../services/web_page_browse_service.dart';
import '../services/web_search_service.dart';

class ChatController extends ChangeNotifier with WidgetsBindingObserver {
  ChatController(
      {required ChatStore chatStore,
      required OpenAiCompatibleClient apiClient,
      required PromptTemplateStore promptTemplateStore,
      WebSearchService? webSearchService,
      WebPageBrowseService? webPageBrowseService,
      int deepResearchMaxRounds = 2})
      : _chatStore = chatStore,
        _apiClient = apiClient,
        _promptTemplateStore = promptTemplateStore,
        _webSearchService = webSearchService ?? WebSearchService(),
        _webPageBrowseService =
            webPageBrowseService ?? WebPageBrowseService(),
        _ownsWebServices = webSearchService == null &&
            webPageBrowseService == null,
        _deepResearchMaxRounds = deepResearchMaxRounds;

  final ChatStore _chatStore;
  final OpenAiCompatibleClient _apiClient;
  final PromptTemplateStore _promptTemplateStore;
  WebSearchService _webSearchService;
  WebPageBrowseService _webPageBrowseService;
  bool _ownsWebServices;
  int _deepResearchMaxRounds;
  ProviderConfig? _lastEffectiveConfig;

  final List<ChatThread> _threads = <ChatThread>[];
  final List<PromptTemplate> _prompts = <PromptTemplate>[];
  String? _selectedThreadId;
  bool _initialized = false;
  bool _isSending = false;
  String? _lastError;
  String? _searchStatus;
  int _nextLocalId = 0;

  List<ChatThread> get threads => List<ChatThread>.unmodifiable(_threads);
  List<PromptTemplate> get prompts =>
      List<PromptTemplate>.unmodifiable(_prompts);
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

    final List<PromptTemplate> storedPrompts =
        await _promptTemplateStore.loadPrompts();
    _prompts
      ..clear()
      ..addAll(storedPrompts);

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

  Future<void> createThreadFromPrompt(PromptTemplate prompt) async {
    final DateTime now = DateTime.now();
    final ChatThread thread = ChatThread(
      id: _newId('thread'),
      title: prompt.name,
      messages: const <ChatMessage>[],
      createdAt: now,
      updatedAt: now,
      isPinned: false,
      promptTemplateId: prompt.id,
      promptTemplateName: prompt.name,
      systemPromptOverride: prompt.systemPrompt,
      modelOverride: prompt.model,
      temperatureOverride: prompt.temperature,
    );
    _threads.insert(0, thread);
    _selectedThreadId = thread.id;
    _lastError = null;
    await _persist();
    notifyListeners();
  }

  // --- Prompt CRUD ---

  Future<void> savePrompt(PromptTemplate prompt) async {
    final int index = _prompts.indexWhere((PromptTemplate p) => p.id == prompt.id);
    if (index == -1) {
      _prompts.add(prompt);
    } else {
      _prompts[index] = prompt;
    }
    await _persistPrompts();
    notifyListeners();
  }

  Future<void> deletePrompt(String promptId) async {
    _prompts.removeWhere((PromptTemplate p) => p.id == promptId);
    await _persistPrompts();
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

  void configureWebSearch({
    String? jinaApiKey,
    String? tavilyApiKey,
    String? firecrawlApiKey,
    String? braveSearchApiKey,
    int deepResearchMaxRounds = 2,
  }) {
    _deepResearchMaxRounds = deepResearchMaxRounds;
    final String? jina =
        (jinaApiKey == null || jinaApiKey.isEmpty) ? null : jinaApiKey;
    final String? tavily =
        (tavilyApiKey == null || tavilyApiKey.isEmpty) ? null : tavilyApiKey;
    final String? firecrawl = (firecrawlApiKey == null ||
            firecrawlApiKey.isEmpty)
        ? null
        : firecrawlApiKey;
    final String? brave = (braveSearchApiKey == null ||
            braveSearchApiKey.isEmpty)
        ? null
        : braveSearchApiKey;

    if (_ownsWebServices) {
      _webSearchService.dispose();
      _webPageBrowseService.dispose();
    }
    _webSearchService =
        WebSearchService(tavilyApiKey: tavily, braveSearchApiKey: brave);
    _webPageBrowseService =
        WebPageBrowseService(jinaApiKey: jina, firecrawlApiKey: firecrawl);
    _ownsWebServices = true;
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

  Future<void> _persistPrompts() async {
    await _promptTemplateStore.savePrompts(_prompts);
  }

  /// Returns a [ProviderConfig] with any per-thread overrides applied.
  ProviderConfig _effectiveConfig(ChatThread thread, ProviderConfig base) {
    return base.copyWith(
      systemPrompt: thread.systemPromptOverride ?? base.systemPrompt,
      model: (thread.modelOverride?.trim().isNotEmpty == true)
          ? thread.modelOverride
          : base.model,
      temperature: thread.temperatureOverride ?? base.temperature,
    );
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

    // Apply any per-thread overrides (from a prompt template) over the global config.
    final ProviderConfig effectiveConfig = _effectiveConfig(thread, config);
    _lastEffectiveConfig = effectiveConfig;

    try {
      // Start the foreground service (and acquire WiFi/wake locks) as early as
      // possible — before web search — so Android cannot cut the network
      // connection if the user backgrounds the app while a request is in flight.
      await RequestForegroundService.start();

      final (List<ChatMessage> requestMessages, List<String> sources) =
          await _buildRequestMessages(
        thread: thread,
        assistantMessage: assistantMessage,
        useWebSearch: useWebSearch,
      );

      // Accumulate the raw (unsanitised) response so that _sanitizeAssistantOutput
      // always operates on the full text.  Storing only the sanitised form between
      // chunks loses structural markers like <think> before the matching </think>
      // has arrived, causing think-block content to leak into the displayed text.
      final StringBuffer rawBuffer = StringBuffer();
      // On Android, Samsung's battery optimiser can cut DNS even with a foreground
      // service.  Retry once after a short pause before surfacing the error.
      const int maxAttempts = 2;
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          await for (final ChatCompletionChunk chunk
              in _apiClient.streamChatCompletion(
            config: effectiveConfig,
            messages: requestMessages,
          )) {
            if (chunk.isDone) {
              final String sanitizedText =
                  _sanitizeAssistantOutput(rawBuffer.toString());
              _updateMessage(
                threadId: thread.id,
                messageId: assistantMessage.id,
                updater: (ChatMessage message) {
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
                  config: effectiveConfig,
                ));
              }
            } else {
              rawBuffer.write(chunk.delta);
              final String sanitizedText =
                  _sanitizeAssistantOutput(rawBuffer.toString());
              _updateMessage(
                threadId: thread.id,
                messageId: assistantMessage.id,
                updater: (ChatMessage message) => message.copyWith(
                  text: sanitizedText,
                  isStreaming: true,
                ),
              );
            }
            notifyListeners();
          }
          break; // success — exit retry loop
        } catch (error) {
          final bool isNetworkError = error.toString().contains('SocketException') ||
              error.toString().contains('Failed host lookup') ||
              error.toString().contains('Connection refused') ||
              error.toString().contains('Connection reset') ||
              error.toString().contains('Connection closed');
          if (isNetworkError && attempt < maxAttempts) {
            // Brief pause to let Android restore DNS after backgrounding.
            await Future<void>.delayed(const Duration(seconds: 2));
            rawBuffer.clear();
            continue;
          }
          rethrow;
        }
      }
    } catch (error) {
      _lastError = error.toString();
      final bool isNetworkError = error.toString().contains('SocketException') ||
          error.toString().contains('Failed host lookup') ||
          error.toString().contains('Connection refused') ||
          error.toString().contains('Connection reset') ||
          error.toString().contains('Connection closed');
      final String errorMessage = isNetworkError
          ? 'Network error — the request could not complete.\n\n'
            'If you backgrounded the app, Android may have cut the '
            'connection. Try disabling battery optimisation for OpenChat '
            'in Android Settings → Apps → OpenChat → Battery.\n\n'
            '${error.toString()}'
          : 'Unable to reach the provider right now. '
            'Check settings and try again.\n\n${error.toString()}';
      _updateMessage(
        threadId: thread.id,
        messageId: assistantMessage.id,
        updater: (ChatMessage message) => message.copyWith(
          text: errorMessage,
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

    final String initialQuery = _buildSearchQuery(requestMessages);

    if (_deepResearchMaxRounds <= 0) {
      // Legacy single-pass behaviour.
      return _singlePassWebSearch(
        requestMessages: requestMessages,
        initialQuery: initialQuery,
      );
    }

    return _deepResearchLoop(
      requestMessages: requestMessages,
      initialQuery: initialQuery,
    );
  }

  Future<(List<ChatMessage>, List<String>)> _singlePassWebSearch({
    required List<ChatMessage> requestMessages,
    required String initialQuery,
  }) async {
    _searchStatus = 'Searching the web…';
    notifyListeners();

    final List<WebSearchResult> results =
        await _webSearchService.search(initialQuery);
    if (results.isEmpty) {
      _searchStatus = null;
      notifyListeners();
      return (requestMessages, const <String>[]);
    }

    _searchStatus = 'Browsing pages…';
    notifyListeners();

    final List<WebPageExcerpt> excerpts = await _webPageBrowseService.browse(
      results,
      query: initialQuery,
    );

    _searchStatus = null;
    notifyListeners();

    final List<String> sources = _collectSources(results, excerpts);
    final ChatMessage contextMessage = _buildContextMessage(
      initialQuery,
      results,
      excerpts,
    );

    return (<ChatMessage>[contextMessage, ...requestMessages], sources);
  }

  Future<(List<ChatMessage>, List<String>)> _deepResearchLoop({
    required List<ChatMessage> requestMessages,
    required String initialQuery,
  }) async {
    final List<(String, List<WebSearchResult>, List<WebPageExcerpt>)>
        allRounds = <(String, List<WebSearchResult>, List<WebPageExcerpt>)>[];
    final Set<String> allFetchedUrls = <String>{};
    final List<String> allSources = <String>[];

    // --- Round 1: use the heuristic query ---
    _searchStatus = 'Researching… (round 1 of $_deepResearchMaxRounds)';
    notifyListeners();

    final List<WebSearchResult> round1Results =
        await _webSearchService.search(initialQuery);

    if (round1Results.isNotEmpty) {
      _searchStatus =
          'Browsing pages… (round 1 of $_deepResearchMaxRounds)';
      notifyListeners();

      final List<WebPageExcerpt> round1Excerpts =
          await _webPageBrowseService.browse(
        round1Results,
        query: initialQuery,
        alreadyFetchedUrls: allFetchedUrls,
      );

      allRounds.add((initialQuery, round1Results, round1Excerpts));
      for (final WebSearchResult r in round1Results) {
        allFetchedUrls.add(r.url);
      }
      for (final WebPageExcerpt e in round1Excerpts) {
        allFetchedUrls.add(e.url);
      }
      allSources.addAll(_collectSources(round1Results, round1Excerpts));
    }

    // --- Rounds 2+: ask the LLM what to search for next ---
    final ProviderConfig? planningConfig = _currentPlanningConfig();

    for (int round = 2;
        round <= _deepResearchMaxRounds && planningConfig != null;
        round += 1) {
      _searchStatus =
          'Planning research… (round $round of $_deepResearchMaxRounds)';
      notifyListeners();

      final List<String> followUpQueries = await _planFollowUpSearches(
        config: planningConfig,
        userQuery: initialQuery,
        completedRounds: allRounds,
      );

      if (followUpQueries.isEmpty) {
        break;
      }

      _searchStatus =
          'Researching… (round $round of $_deepResearchMaxRounds)';
      notifyListeners();

      final List<WebSearchResult> roundResults =
          await _webSearchService.searchAll(
        followUpQueries,
        maxResultsPerQuery: 4,
      );

      if (roundResults.isEmpty) {
        break;
      }

      _searchStatus =
          'Browsing pages… (round $round of $_deepResearchMaxRounds)';
      notifyListeners();

      final String combinedQuery = followUpQueries.join('; ');
      final List<WebPageExcerpt> roundExcerpts =
          await _webPageBrowseService.browse(
        roundResults,
        query: combinedQuery,
        alreadyFetchedUrls: allFetchedUrls,
      );

      allRounds.add((combinedQuery, roundResults, roundExcerpts));
      for (final WebSearchResult r in roundResults) {
        allFetchedUrls.add(r.url);
      }
      for (final WebPageExcerpt e in roundExcerpts) {
        allFetchedUrls.add(e.url);
      }
      allSources.addAll(_collectSources(roundResults, roundExcerpts));
    }

    _searchStatus = null;
    notifyListeners();

    if (allRounds.isEmpty) {
      return (requestMessages, const <String>[]);
    }

    final StringBuffer contextBuffer = StringBuffer();
    for (int i = 0; i < allRounds.length; i += 1) {
      final (String query, List<WebSearchResult> results,
          List<WebPageExcerpt> excerpts) = allRounds[i];
      if (i > 0) {
        contextBuffer.writeln();
        contextBuffer.writeln('---');
        contextBuffer.writeln();
      }
      contextBuffer.write(
        _webPageBrowseService.formatBrowseContext(query, results, excerpts),
      );
    }

    final ChatMessage contextMessage = ChatMessage(
      id: _newId('message'),
      role: ChatRole.system,
      text: contextBuffer.toString().trim(),
      createdAt: DateTime.now(),
      attachments: const <ChatAttachment>[],
      isStreaming: false,
      isError: false,
    );

    final Set<String> seenSources = <String>{};
    final List<String> dedupedSources = allSources
        .where((String s) => seenSources.add(s))
        .toList(growable: false);

    return (<ChatMessage>[contextMessage, ...requestMessages], dedupedSources);
  }

  /// Asks the LLM for follow-up search queries based on what has been found so far.
  /// Returns a list of 0–3 queries. Returns empty list if more research is not needed
  /// or if the planning call fails.
  Future<List<String>> _planFollowUpSearches({
    required ProviderConfig config,
    required String userQuery,
    required List<(String, List<WebSearchResult>, List<WebPageExcerpt>)>
        completedRounds,
  }) async {
    final StringBuffer summary = StringBuffer();
    for (final (String query, List<WebSearchResult> results,
        List<WebPageExcerpt> excerpts) in completedRounds) {
      summary.writeln('Query: "$query"');
      for (final WebSearchResult r in results.take(5)) {
        final String snippet = r.snippet.length > 120
            ? '${r.snippet.substring(0, 120)}…'
            : r.snippet;
        summary.writeln('  [result] ${r.title}: $snippet');
      }
      for (final WebPageExcerpt e in excerpts.take(3)) {
        final String excerpt = e.excerpt.length > 200
            ? '${e.excerpt.substring(0, 200)}…'
            : e.excerpt;
        summary.writeln('  [page] ${e.title}: $excerpt');
      }
    }

    const String systemPrompt =
        'You are a research planner deciding whether more web searches are '
        'needed. Default to DONE — only request follow-up searches if there '
        'is a clear, specific gap in the evidence that extra searches would '
        'fill. If the gathered results already cover the question, reply with '
        'the single word DONE. If and only if a specific gap exists, reply '
        'with a newline-separated list of up to 3 targeted search queries '
        '(no numbering, no explanations, nothing else).';

    final String userContent =
        'User question: $userQuery\n\n'
        'Research gathered so far:\n${summary.toString().trim()}\n\n'
        'Is the research sufficient to fully answer the question? '
        'Reply DONE or list specific follow-up queries.';

    final String? response = await _apiClient.completeChat(
      config: config,
      messages: <Map<String, dynamic>>[
        <String, dynamic>{'role': 'system', 'content': systemPrompt},
        <String, dynamic>{'role': 'user', 'content': userContent},
      ],
      maxTokens: 150,
      temperature: 0.2,
    );

    if (response == null || response.trim().toUpperCase() == 'DONE') {
      return const <String>[];
    }

    return response
        .split('\n')
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty && line.toUpperCase() != 'DONE')
        .take(3)
        .toList(growable: false);
  }

  /// Returns the effective [ProviderConfig] to use for planning calls,
  /// or `null` if no valid config is available.
  ProviderConfig? _currentPlanningConfig() {
    final ChatThread? thread = currentThread;
    if (thread == null) {
      return null;
    }
    return _lastEffectiveConfig;
  }

  List<String> _collectSources(
    List<WebSearchResult> results,
    List<WebPageExcerpt> excerpts,
  ) {
    return <String>[
      for (final WebSearchResult r in results) r.url,
      for (final WebPageExcerpt e in excerpts)
        if (!results.any((WebSearchResult r) => r.url == e.url)) e.url,
    ];
  }

  ChatMessage _buildContextMessage(
    String query,
    List<WebSearchResult> results,
    List<WebPageExcerpt> excerpts,
  ) {
    return ChatMessage(
      id: _newId('message'),
      role: ChatRole.system,
      text: _webPageBrowseService.formatBrowseContext(query, results, excerpts),
      createdAt: DateTime.now(),
      attachments: const <ChatAttachment>[],
      isStreaming: false,
      isError: false,
    );
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
        // Pass 1: remove complete <think>...</think> blocks.
        .replaceAll(
          RegExp(r'<think\b[^>]*>.*?</think>', caseSensitive: false, dotAll: true),
          ' ',
        )
        // Pass 2: remove any unclosed <think> block that is still arriving —
        // i.e. everything from a lone opening tag to the end of the string.
        // This prevents think-block content from leaking into the UI during
        // streaming before the closing </think> has been received.
        .replaceAll(
          RegExp(r'<think\b[^>]*>.*$', caseSensitive: false, dotAll: true),
          '',
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
