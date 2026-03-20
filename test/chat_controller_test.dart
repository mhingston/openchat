import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openchat/src/controllers/chat_controller.dart';
import 'package:openchat/src/models/attachment.dart';
import 'package:openchat/src/models/chat_message.dart';
import 'package:openchat/src/models/chat_thread.dart';
import 'package:openchat/src/models/provider_config.dart';
import 'package:openchat/src/services/chat_store.dart';
import 'package:openchat/src/services/openai_compatible_client.dart';
import 'package:openchat/src/services/prompt_template_store.dart';
import 'package:openchat/src/services/web_page_browse_service.dart';
import 'package:openchat/src/services/web_search_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatController', () {
    test('initialize keeps an honest empty state with no stored threads',
        () async {
      final ({ChatController controller, ChatStore store}) setup =
          await _createController();

      expect(setup.controller.threads, isEmpty);
      expect(setup.controller.currentThread, isNull);
      expect(await setup.store.loadThreads(), isEmpty);
    });

    test('renameThread trims the title and persists it', () async {
      final ({ChatController controller, ChatStore store}) setup =
          await _createController();

      await setup.controller.createThread();
      final String threadId = setup.controller.currentThread!.id;

      await setup.controller.renameThread(threadId, '  Project kickoff  ');

      expect(setup.controller.currentThread!.title, 'Project kickoff');
      expect((await setup.store.loadThreads()).single.title, 'Project kickoff');
    });

    test('duplicateThread copies a conversation and selects the new thread',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final ChatStore store = ChatStore(preferences);
      final DateTime timestamp = DateTime(2026, 3, 16, 12, 0);
      await store.saveThreads(<ChatThread>[
        ChatThread(
          id: 'thread-1',
          title: 'Sprint planning',
          messages: <ChatMessage>[
            ChatMessage(
              id: 'message-1',
              role: ChatRole.user,
              text: 'Summarize this sprint.',
              createdAt: timestamp,
              attachments: const [],
              isStreaming: false,
              isError: false,
            ),
          ],
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      ]);

      final ChatController controller = ChatController(
        chatStore: store,
        promptTemplateStore: PromptTemplateStore(preferences),
        apiClient: _createClient(),
      );
      await controller.initialize();

      await controller.duplicateThread('thread-1');

      expect(controller.threads, hasLength(2));
      expect(controller.currentThread, isNotNull);
      expect(controller.currentThread!.id, isNot('thread-1'));
      expect(controller.currentThread!.title, 'Sprint planning (copy)');
      expect(controller.currentThread!.messages, hasLength(1));
      expect(controller.currentThread!.messages.single.id, isNot('message-1'));
      expect(
          (await store.loadThreads()).map((ChatThread thread) => thread.title),
          containsAll(<String>[
            'Sprint planning',
            'Sprint planning (copy)',
          ]));
    });

    test(
        'deleteThread removes the last conversation without forcing a blank one',
        () async {
      final ({ChatController controller, ChatStore store}) setup =
          await _createController();

      await setup.controller.createThread();
      final String threadId = setup.controller.currentThread!.id;

      await setup.controller.deleteThread(threadId);

      expect(setup.controller.threads, isEmpty);
      expect(setup.controller.currentThread, isNull);
      expect(await setup.store.loadThreads(), isEmpty);
    });

    test(
        'sendMessage creates and keeps the selected thread when starting from empty',
        () async {
      final ({ChatController controller, ChatStore store}) setup =
          await _createController();
      const ProviderConfig config = ProviderConfig(
        presetId: 'openai',
        label: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        model: 'gpt-4o-mini',
        systemPrompt: '',
        temperature: 1.0,
        streamResponses: false,
      );

      await setup.controller.sendMessage(
        text: 'Hello there',
        attachments: const [],
        config: config,
      );

      expect(setup.controller.currentThread, isNotNull);
      expect(setup.controller.threads, hasLength(1));
      expect(setup.controller.currentThread!.messages, hasLength(2));
      expect((await setup.store.loadThreads()), hasLength(1));
    });

    test('sendMessage can augment the request with web search context',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final ChatStore store = ChatStore(preferences);
      late Map<String, dynamic> requestBody;
      final ChatController controller = ChatController(
        chatStore: store,
        promptTemplateStore: PromptTemplateStore(preferences),
        apiClient: OpenAiCompatibleClient(
          isWebOverride: false,
          httpClient: MockClient((http.Request request) async {
            requestBody = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode(<String, Object>{
                'choices': <Map<String, Object>>[
                  <String, Object>{
                    'message': <String, String>{'content': 'Assistant reply'},
                  },
                ],
              }),
              200,
            );
          }),
        ),
        webSearchService: WebSearchService(
          isWebOverride: false,
          httpClient: MockClient((http.Request request) async {
            return http.Response(
              '''
<html><body>
  <div class="result results_links results_links_deep web-result">
    <div class="links_main links_deep result__body">
      <h2 class="result__title">
        <a class="result__a" href="https://example.com/openchat">OpenChat</a>
      </h2>
      <a class="result__snippet">OpenChat is a chat client.</a>
    </div>
  </div>
</body></html>
''',
              200,
            );
          }),
        ),
        webPageBrowseService: WebPageBrowseService(
          isWebOverride: false,
          httpClient: MockClient((http.Request request) async {
            // Return 404 for Jina Reader requests so the service falls back
            // to direct HTML fetching (which these mocks provide).
            if (request.url.host == 'r.jina.ai') {
              return http.Response('', 404);
            }
            if (request.url.toString() == 'https://example.com/openchat') {
              return http.Response(
                '''
<html>
  <head>
    <title>OpenChat release notes</title>
    <style>.hidden { display: none; }</style>
  </head>
  <body>
    <script>console.log("ignore this");</script>
    <main>
      <h1>OpenChat release notes</h1>
      <p>OpenChat shipped a lightweight browse mode today.</p>
      <a href="/openchat/story-1">Browse mode now loads source pages for better citations</a>
    </main>
  </body>
</html>
''',
                200,
              );
            }

            return http.Response(
              '''
<html>
  <head>
    <title>Browse mode article</title>
  </head>
  <body>
    <main><p>It fetches web pages and cites sources in answers.</p></main>
  </body>
</html>
''',
              200,
            );
          }),
        ),
      );
      await controller.initialize();

      const ProviderConfig config = ProviderConfig(
        presetId: 'openai',
        label: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        model: 'gpt-4o-mini',
        systemPrompt: '',
        temperature: 1.0,
        streamResponses: false,
      );

      await controller.sendMessage(
        text: 'What happened today?',
        attachments: const [],
        config: config,
        useWebSearch: true,
      );

      final List<dynamic> messages = requestBody['messages'] as List<dynamic>;
      expect(messages.first['role'], 'system');
      expect(messages.first['content'], contains('Web browse context for:'));
      expect(
          messages.first['content'], contains('https://example.com/openchat'));
      expect(
        messages.first['content'],
        contains('OpenChat shipped a lightweight browse mode today.'),
      );
      expect(
        messages.first['content'],
        contains('It fetches web pages and cites sources in answers.'),
      );
      expect(messages.first['content'], contains('Do not mention tools'));
      expect(messages.first['content'], contains('Latest extracted headlines:'));
      expect(messages.first['content'], contains('Sources:'));
    });

    test('sendMessage strips leaked tool and think markup from responses',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final ChatStore store = ChatStore(preferences);
      final ChatController controller = ChatController(
        chatStore: store,
        promptTemplateStore: PromptTemplateStore(preferences),
        apiClient: OpenAiCompatibleClient(
          isWebOverride: false,
          httpClient: MockClient((http.Request request) async {
            return http.Response(
              jsonEncode(<String, Object>{
                'choices': <Map<String, Object>>[
                  <String, Object>{
                    'message': <String, String>{
                      'content':
                          'I\'ll fetch the homepage.\n\n'
                          'Fetching BBC News...\n\n'
                          'tool_call(requests): [\n'
                          '{"url": "https://www.bbc.com/news"}\n'
                          ']\n\n'
                          '<think>hidden reasoning</think>\n'
                          'Let me extract the top stories for you.\n\n'
                          'Based on the live BBC News page embedded above, here are the latest headlines.\n\n'
                          'Top BBC headlines include major world and UK updates [1].',
                    },
                  },
                ],
              }),
              200,
            );
          }),
        ),
      );
      await controller.initialize();

      const ProviderConfig config = ProviderConfig(
        presetId: 'openai',
        label: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        model: 'gpt-4o-mini',
        systemPrompt: '',
        temperature: 1.0,
        streamResponses: false,
      );

      await controller.sendMessage(
        text: 'What is on BBC News?',
        attachments: const [],
        config: config,
      );

      final ChatMessage assistantMessage =
          controller.currentThread!.messages.last;
      expect(assistantMessage.role, ChatRole.assistant);
      expect(assistantMessage.text, isNot(contains('tool_call(')));
      expect(assistantMessage.text, isNot(contains('<think>')));
      expect(assistantMessage.text, isNot(contains('Fetching BBC News')));
      expect(assistantMessage.text, isNot(contains('Let me extract')));
      expect(assistantMessage.text, contains('Top BBC headlines include'));
    });

    // Regression: during Ollama streaming, think-block content and tags must
    // never appear in any intermediate or final message text.  Earlier builds
    // showed raw </think> in the UI because the streaming sanitizer stripped
    // the opening <think> tag while leaving the content between the tags
    // visible until </think> arrived in a later chunk.
    test(
        'streaming think block content does not appear in any intermediate '
        'message snapshot', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final ChatStore store = ChatStore(preferences);

      // Simulate an Ollama model that streams a think block across several
      // chunks, followed by the actual answer.
      final List<String> ollamaChunks = <String>[
        '{"message":{"role":"assistant","content":"<think>"},"done":false}\n',
        '{"message":{"role":"assistant","content":"internal reasoning here"},"done":false}\n',
        '{"message":{"role":"assistant","content":"</think>"},"done":false}\n',
        '{"message":{"role":"assistant","content":"The answer is 42."},"done":false}\n',
        '{"done":true}\n',
      ];

      final ChatController controller = ChatController(
        chatStore: store,
        promptTemplateStore: PromptTemplateStore(preferences),
        apiClient: OpenAiCompatibleClient(
          isWebOverride: false,
          httpClient: _StreamingClient(ollamaChunks),
        ),
      );
      await controller.initialize();

      // Capture every intermediate text value the controller emits.
      final List<String> snapshots = <String>[];
      controller.addListener(() {
        final String? text = controller.currentThread?.messages.last.text;
        if (text != null) snapshots.add(text);
      });

      await controller.sendMessage(
        text: 'What is 6 * 7?',
        attachments: const <ChatAttachment>[],
        config: const ProviderConfig(
          presetId: 'ollama-cloud',
          label: 'Ollama Cloud',
          baseUrl: 'https://ollama.com',
          apiKey: 'test-key',
          model: 'llama3',
          systemPrompt: '',
          temperature: 1.0,
          streamResponses: true,
        ),
      );

      expect(snapshots, isNotEmpty, reason: 'Expected streaming snapshots');

      for (final String snapshot in snapshots) {
        expect(
          snapshot,
          isNot(contains('<think>')),
          reason: 'Think opening tag leaked into streamed text: "$snapshot"',
        );
        expect(
          snapshot,
          isNot(contains('</think>')),
          reason: 'Think closing tag leaked into streamed text: "$snapshot"',
        );
        expect(
          snapshot,
          isNot(contains('internal reasoning here')),
          reason: 'Think content leaked into streamed text: "$snapshot"',
        );
      }

      final ChatMessage finalMessage =
          controller.currentThread!.messages.last;
      expect(finalMessage.text, contains('42'));
      expect(finalMessage.text, isNot(contains('<think>')));
      expect(finalMessage.text, isNot(contains('</think>')));
      expect(finalMessage.text, isNot(contains('internal reasoning here')));
    });

    test('sendMessage falls back to search snippets when page browsing fails',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final ChatStore store = ChatStore(preferences);
      late Map<String, dynamic> requestBody;
      final ChatController controller = ChatController(
        chatStore: store,
        promptTemplateStore: PromptTemplateStore(preferences),
        apiClient: OpenAiCompatibleClient(
          isWebOverride: false,
          httpClient: MockClient((http.Request request) async {
            requestBody = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode(<String, Object>{
                'choices': <Map<String, Object>>[
                  <String, Object>{
                    'message': <String, String>{'content': 'Assistant reply'},
                  },
                ],
              }),
              200,
            );
          }),
        ),
        webSearchService: WebSearchService(
          isWebOverride: false,
          httpClient: MockClient((http.Request request) async {
            return http.Response(
              '''
<html><body>
  <div class="result results_links results_links_deep web-result">
    <div class="links_main links_deep result__body">
      <h2 class="result__title">
        <a class="result__a" href="https://example.com/openchat">OpenChat</a>
      </h2>
      <a class="result__snippet">Search snippet only.</a>
    </div>
  </div>
</body></html>
''',
              200,
            );
          }),
        ),
        webPageBrowseService: WebPageBrowseService(
          isWebOverride: false,
          httpClient: MockClient((http.Request request) async {
            return http.Response('blocked', 403);
          }),
        ),
      );
      await controller.initialize();

      const ProviderConfig config = ProviderConfig(
        presetId: 'openai',
        label: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        model: 'gpt-4o-mini',
        systemPrompt: '',
        temperature: 1.0,
        streamResponses: false,
      );

      await controller.sendMessage(
        text: 'What happened today?',
        attachments: const [],
        config: config,
        useWebSearch: true,
      );

      final List<dynamic> messages = requestBody['messages'] as List<dynamic>;
      expect(messages.first['role'], 'system');
      expect(messages.first['content'], contains('Search snippet only.'));
      expect(messages.first['content'], isNot(contains('Fetched page excerpts:')));
    });

    test('deleteMessage removes a message and persists the updated thread',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final ChatStore store = ChatStore(preferences);
      final DateTime timestamp = DateTime(2026, 3, 16, 12, 0);
      await store.saveThreads(<ChatThread>[
        ChatThread(
          id: 'thread-1',
          title: 'Sprint planning',
          messages: <ChatMessage>[
            ChatMessage(
              id: 'message-1',
              role: ChatRole.user,
              text: 'First',
              createdAt: timestamp,
              attachments: const [],
              isStreaming: false,
              isError: false,
            ),
            ChatMessage(
              id: 'message-2',
              role: ChatRole.assistant,
              text: 'Second',
              createdAt: timestamp,
              attachments: const [],
              isStreaming: false,
              isError: false,
            ),
          ],
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      ]);

      final ChatController controller = ChatController(
        chatStore: store,
        promptTemplateStore: PromptTemplateStore(preferences),
        apiClient: _createClient(),
      );
      await controller.initialize();

      await controller.deleteMessage(
        threadId: 'thread-1',
        messageId: 'message-1',
      );

      expect(controller.currentThread, isNotNull);
      expect(controller.currentThread!.messages, hasLength(1));
      expect(controller.currentThread!.messages.single.id, 'message-2');
      expect((await store.loadThreads()).single.messages, hasLength(1));
    });

    test('retryMessage replaces the failed last assistant message', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final ChatStore store = ChatStore(preferences);
      final DateTime timestamp = DateTime(2026, 3, 16, 12, 0);
      await store.saveThreads(<ChatThread>[
        ChatThread(
          id: 'thread-1',
          title: 'Sprint planning',
          messages: <ChatMessage>[
            ChatMessage(
              id: 'message-1',
              role: ChatRole.user,
              text: 'Summarize this sprint.',
              createdAt: timestamp,
              attachments: const [],
              isStreaming: false,
              isError: false,
            ),
            ChatMessage(
              id: 'message-2',
              role: ChatRole.assistant,
              text: 'Unable to reach the provider right now.',
              createdAt: timestamp,
              attachments: const [],
              isStreaming: false,
              isError: true,
            ),
          ],
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      ]);

      final ChatController controller = ChatController(
        chatStore: store,
        promptTemplateStore: PromptTemplateStore(preferences),
        apiClient: _createClient(),
      );
      await controller.initialize();

      await controller.retryMessage(
        threadId: 'thread-1',
        messageId: 'message-2',
        config: const ProviderConfig(
          presetId: 'openai',
          label: 'OpenAI',
          baseUrl: 'https://api.openai.com/v1',
          apiKey: 'sk-test',
          model: 'gpt-4o-mini',
          systemPrompt: '',
          temperature: 1.0,
          streamResponses: false,
        ),
      );

      expect(controller.currentThread, isNotNull);
      expect(controller.currentThread!.messages, hasLength(2));
      final ChatMessage retriedMessage =
          controller.currentThread!.messages.last;
      expect(retriedMessage.role, ChatRole.assistant);
      expect(retriedMessage.text, 'Assistant reply');
      expect(retriedMessage.isError, isFalse);
      expect(retriedMessage.isStreaming, isFalse);
    });

    test('editUserMessageAndResubmit truncates later history and replays reply',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final ChatStore store = ChatStore(preferences);
      final DateTime timestamp = DateTime(2026, 3, 16, 12, 0);
      await store.saveThreads(<ChatThread>[
        ChatThread(
          id: 'thread-1',
          title: 'Sprint planning',
          messages: <ChatMessage>[
            ChatMessage(
              id: 'message-1',
              role: ChatRole.user,
              text: 'Original prompt',
              createdAt: timestamp,
              attachments: <ChatAttachment>[
                ChatAttachment(
                  id: 'attachment-1',
                  name: 'notes.txt',
                  kind: AttachmentKind.file,
                  mimeType: 'text/plain',
                  sizeBytes: 5,
                  previewText: 'notes',
                  createdAt: timestamp,
                ),
              ],
              isStreaming: false,
              isError: false,
            ),
            ChatMessage(
              id: 'message-2',
              role: ChatRole.assistant,
              text: 'Old answer',
              createdAt: timestamp,
              attachments: const <ChatAttachment>[],
              isStreaming: false,
              isError: false,
            ),
            ChatMessage(
              id: 'message-3',
              role: ChatRole.user,
              text: 'Follow-up',
              createdAt: timestamp,
              attachments: const <ChatAttachment>[],
              isStreaming: false,
              isError: false,
            ),
          ],
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      ]);

      final ChatController controller = ChatController(
        chatStore: store,
        promptTemplateStore: PromptTemplateStore(preferences),
        apiClient: _createClient(),
      );
      await controller.initialize();

      final bool edited = await controller.editUserMessageAndResubmit(
        threadId: 'thread-1',
        messageId: 'message-1',
        text: 'Edited prompt',
        attachments: const <ChatAttachment>[],
        config: const ProviderConfig(
          presetId: 'openai',
          label: 'OpenAI',
          baseUrl: 'https://api.openai.com/v1',
          apiKey: 'sk-test',
          model: 'gpt-4o-mini',
          systemPrompt: '',
          temperature: 1.0,
          streamResponses: false,
        ),
      );

      expect(edited, isTrue);
      expect(controller.currentThread, isNotNull);
      expect(controller.currentThread!.messages, hasLength(2));
      expect(controller.currentThread!.messages.first.text, 'Edited prompt');
      expect(controller.currentThread!.messages.first.attachments, isEmpty);
      expect(controller.currentThread!.messages.last.role, ChatRole.assistant);
      expect(controller.currentThread!.messages.last.text, 'Assistant reply');
    });

    test('forkFromUserMessage creates a new thread from the selected branch',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final ChatStore store = ChatStore(preferences);
      final DateTime timestamp = DateTime(2026, 3, 16, 12, 0);
      await store.saveThreads(<ChatThread>[
        ChatThread(
          id: 'thread-1',
          title: 'Sprint planning',
          messages: <ChatMessage>[
            ChatMessage(
              id: 'message-1',
              role: ChatRole.user,
              text: 'Original prompt',
              createdAt: timestamp,
              attachments: const <ChatAttachment>[],
              isStreaming: false,
              isError: false,
            ),
            ChatMessage(
              id: 'message-2',
              role: ChatRole.assistant,
              text: 'Old answer',
              createdAt: timestamp,
              attachments: const <ChatAttachment>[],
              isStreaming: false,
              isError: false,
            ),
            ChatMessage(
              id: 'message-3',
              role: ChatRole.user,
              text: 'Branch from here',
              createdAt: timestamp,
              attachments: const <ChatAttachment>[],
              isStreaming: false,
              isError: false,
            ),
            ChatMessage(
              id: 'message-4',
              role: ChatRole.assistant,
              text: 'Later answer',
              createdAt: timestamp,
              attachments: const <ChatAttachment>[],
              isStreaming: false,
              isError: false,
            ),
          ],
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      ]);

      final ChatController controller = ChatController(
        chatStore: store,
        promptTemplateStore: PromptTemplateStore(preferences),
        apiClient: _createClient(),
      );
      await controller.initialize();

      final bool forked = await controller.forkFromUserMessage(
        threadId: 'thread-1',
        messageId: 'message-3',
        config: const ProviderConfig(
          presetId: 'openai',
          label: 'OpenAI',
          baseUrl: 'https://api.openai.com/v1',
          apiKey: 'sk-test',
          model: 'gpt-4o-mini',
          systemPrompt: '',
          temperature: 1.0,
          streamResponses: false,
        ),
      );

      expect(forked, isTrue);
      expect(controller.threads, hasLength(2));
      expect(controller.currentThread, isNotNull);
      expect(controller.currentThread!.title, 'Sprint planning (fork)');
      expect(controller.currentThread!.messages, hasLength(4));
      expect(controller.currentThread!.messages[2].text, 'Branch from here');
      expect(controller.currentThread!.messages.last.text, 'Assistant reply');
      expect(
        controller.currentThread!.messages
            .map((ChatMessage message) => message.id),
        isNot(contains('message-3')),
      );
    });

    test('importThreads merges imported chats into existing history', () async {
      final ({ChatController controller, ChatStore store}) setup =
          await _createController();
      await setup.controller.createThread();

      final int importedCount = await setup.controller.importThreads(
        threads: <ChatThread>[
          ChatThread(
            id: 'thread-imported',
            title: 'Imported thread',
            messages: <ChatMessage>[
              ChatMessage(
                id: 'message-imported',
                role: ChatRole.user,
                text: 'Imported text',
                createdAt: DateTime(2026, 3, 16, 12, 0),
                attachments: const [],
                isStreaming: false,
                isError: false,
              ),
            ],
            createdAt: DateTime(2026, 3, 16, 12, 0),
            updatedAt: DateTime(2026, 3, 16, 12, 0),
          ),
        ],
        replaceExisting: false,
      );

      expect(importedCount, 1);
      expect(setup.controller.threads, hasLength(2));
      expect(setup.controller.currentThread, isNotNull);
      expect(setup.controller.currentThread!.title, 'Imported thread');
      expect(setup.controller.currentThread!.id, isNot('thread-imported'));
      expect((await setup.store.loadThreads()), hasLength(2));
    });

    test('importThreads can replace existing chats', () async {
      final ({ChatController controller, ChatStore store}) setup =
          await _createController();
      await setup.controller.createThread();

      final int importedCount = await setup.controller.importThreads(
        threads: <ChatThread>[
          ChatThread(
            id: 'thread-imported',
            title: 'Replacement thread',
            messages: const [],
            createdAt: DateTime(2026, 3, 16, 12, 0),
            updatedAt: DateTime(2026, 3, 16, 12, 0),
          ),
        ],
        replaceExisting: true,
      );

      expect(importedCount, 1);
      expect(setup.controller.threads, hasLength(1));
      expect(setup.controller.currentThread!.title, 'Replacement thread');
      expect(
          (await setup.store.loadThreads()).single.title, 'Replacement thread');
    });

    test('togglePinnedThread persists pinned threads and moves them to the top',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final ChatStore store = ChatStore(preferences);
      await store.saveThreads(<ChatThread>[
        ChatThread(
          id: 'thread-1',
          title: 'Older thread',
          messages: const <ChatMessage>[],
          createdAt: DateTime(2026, 3, 16, 10),
          updatedAt: DateTime(2026, 3, 16, 10),
        ),
        ChatThread(
          id: 'thread-2',
          title: 'Newest thread',
          messages: const <ChatMessage>[],
          createdAt: DateTime(2026, 3, 16, 11),
          updatedAt: DateTime(2026, 3, 16, 11),
        ),
      ]);

      final ChatController controller = ChatController(
        chatStore: store,
        promptTemplateStore: PromptTemplateStore(preferences),
        apiClient: _createClient(),
      );
      await controller.initialize();

      await controller.togglePinnedThread('thread-1');

      expect(controller.threads.first.id, 'thread-1');
      expect(controller.threads.first.isPinned, isTrue);
      expect((await store.loadThreads()).first.isPinned, isTrue);
    });

    test('searchThreads matches titles and message content', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final ChatStore store = ChatStore(preferences);
      await store.saveThreads(<ChatThread>[
        ChatThread(
          id: 'thread-1',
          title: 'Release checklist',
          messages: const <ChatMessage>[],
          createdAt: DateTime(2026, 3, 16, 10),
          updatedAt: DateTime(2026, 3, 16, 10),
        ),
        ChatThread(
          id: 'thread-2',
          title: 'Support follow-up',
          messages: <ChatMessage>[
            ChatMessage(
              id: 'message-1',
              role: ChatRole.assistant,
              text: 'We should prepare the release notes today.',
              createdAt: DateTime(2026, 3, 16, 12),
              attachments: const [],
              isStreaming: false,
              isError: false,
            ),
          ],
          createdAt: DateTime(2026, 3, 16, 11),
          updatedAt: DateTime(2026, 3, 16, 12),
        ),
      ]);

      final ChatController controller = ChatController(
        chatStore: store,
        promptTemplateStore: PromptTemplateStore(preferences),
        apiClient: _createClient(),
      );
      await controller.initialize();

      final results = controller.searchThreads('release');

      expect(results, hasLength(2));
      expect(results.any((result) => result.matchesTitle), isTrue);
      expect(
        results.any(
          (result) =>
              result.messageId == 'message-1' &&
              result.matchLabel == 'Assistant message',
        ),
        isTrue,
      );
    });
  });
}

Future<({ChatController controller, ChatStore store})>
    _createController() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences preferences = await SharedPreferences.getInstance();
  final ChatStore store = ChatStore(preferences);
  final ChatController controller = ChatController(
    chatStore: store,
        promptTemplateStore: PromptTemplateStore(preferences),
    apiClient: _createClient(),
  );
  await controller.initialize();
  return (controller: controller, store: store);
}

OpenAiCompatibleClient _createClient() {
  return OpenAiCompatibleClient(
    isWebOverride: false,
    httpClient: MockClient((http.Request request) async {
      final String path = request.url.path;
      if (path.endsWith('/chat/completions')) {
        return http.Response(
          jsonEncode(<String, Object>{
            'choices': <Map<String, Object>>[
              <String, Object>{
                'message': <String, String>{'content': 'Assistant reply'},
              },
            ],
          }),
          200,
        );
      }

      return http.Response('{}', 200);
    }),
  );
}

// A minimal HTTP client that returns a pre-baked list of byte chunks as a
// true streaming response.  Used to simulate Ollama streaming SSE output
// arriving in separate packets.
class _StreamingClient extends http.BaseClient {
  _StreamingClient(this._lines);

  final List<String> _lines;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final StreamController<List<int>> controller =
        StreamController<List<int>>();
    Future.microtask(() async {
      for (final String line in _lines) {
        controller.add(utf8.encode(line));
        // Yield between chunks so the controller's listener can process each
        // one independently, mirroring real network packet delivery.
        await Future<void>.delayed(Duration.zero);
      }
      await controller.close();
    });
    return http.StreamedResponse(controller.stream, 200);
  }
}
