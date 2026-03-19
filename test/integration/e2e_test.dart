// Integration (E2E) tests that hit real network endpoints.
//
// Configure via environment variables before running:
//
//   OPENCHAT_TEST_BASE_URL   – API base URL
//                              Ollama local:  http://localhost:11434
//                              Ollama Cloud:  https://ollama.com
//                              OpenRouter:    https://openrouter.ai/api/v1
//   OPENCHAT_TEST_API_KEY    – API key (leave empty for local Ollama)
//   OPENCHAT_TEST_MODEL      – Model name to use, e.g. "llama3.2" or "glm-5"
//   OPENCHAT_TEST_PRESET     – Preset ID: "custom" | "ollama-cloud" | "openai"
//                              (default: "custom" for OpenAI-compatible,
//                               "ollama-local" for localhost)
//
// Run with:
//   flutter test test/integration/e2e_test.dart
//   flutter test test/integration/e2e_test.dart --name "web search"
//
// These tests are skipped automatically when OPENCHAT_TEST_BASE_URL is unset.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:openchat/src/models/attachment.dart';
import 'package:openchat/src/models/chat_message.dart';
import 'package:openchat/src/models/provider_config.dart';
import 'package:openchat/src/services/openai_compatible_client.dart';
import 'package:openchat/src/services/web_page_browse_service.dart';
import 'package:openchat/src/services/web_search_service.dart';
import 'package:openchat/src/models/web_search_result.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openchat/src/controllers/chat_controller.dart';
import 'package:openchat/src/services/chat_store.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ProviderConfig? _buildConfig() {
  final String? baseUrl = Platform.environment['OPENCHAT_TEST_BASE_URL'];
  if (baseUrl == null || baseUrl.isEmpty) return null;

  final String apiKey = Platform.environment['OPENCHAT_TEST_API_KEY'] ?? '';
  final String model = Platform.environment['OPENCHAT_TEST_MODEL'] ?? '';
  final String rawPreset = Platform.environment['OPENCHAT_TEST_PRESET'] ?? '';

  // Auto-detect preset from URL when not specified.
  final String presetId = rawPreset.isNotEmpty
      ? rawPreset
      : baseUrl.contains('localhost') || baseUrl.contains('127.0.0.1')
          ? 'ollama-local'
          : 'custom';

  return ProviderConfig(
    presetId: presetId,
    label: 'E2E test provider',
    baseUrl: baseUrl,
    apiKey: apiKey,
    model: model,
    systemPrompt: '',
    temperature: 0.1,
    streamResponses: true,
  );
}

void _skipIfUnconfigured(ProviderConfig? config) {
  if (config == null) {
    markTestSkipped(
      'Skipped: set OPENCHAT_TEST_BASE_URL (and optionally '
      'OPENCHAT_TEST_API_KEY / OPENCHAT_TEST_MODEL) to run E2E tests.',
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // flutter test's TestWidgetsFlutterBinding intercepts all dart:io HTTP and
  // returns 400.  Integration tests need real network access, so we clear the
  // override immediately after the binding is initialised.
  setUpAll(() {
    WidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
  });
  TestWidgetsFlutterBinding.ensureInitialized();

  final ProviderConfig? config = _buildConfig();

  // ── Provider / LLM tests ─────────────────────────────────────────────────

  group('Provider connectivity', () {
    test('listModels returns at least one model', () async {
      _skipIfUnconfigured(config);
      final OpenAiCompatibleClient client = OpenAiCompatibleClient(
        isWebOverride: false,
      );
      addTearDown(client.dispose);

      final List<String> models = await client.listModels(config: config!);
      expect(models, isNotEmpty, reason: 'Expected at least one available model');
    });
  });

  group('Chat completion', () {
    test('streams a non-empty response to a simple prompt', () async {
      _skipIfUnconfigured(config);
      final OpenAiCompatibleClient client = OpenAiCompatibleClient(
        isWebOverride: false,
      );
      addTearDown(client.dispose);

      final StringBuffer response = StringBuffer();
      await for (final ChatCompletionChunk chunk in client.streamChatCompletion(
        config: config!,
        messages: <ChatMessage>[
          ChatMessage(
            id: 'm1',
            role: ChatRole.user,
            text: 'Reply with exactly: PONG',
            createdAt: DateTime.now(),
            attachments: const <ChatAttachment>[],
            isStreaming: false,
            isError: false,
          ),
        ],
      )) {
        if (!chunk.isDone) response.write(chunk.delta);
      }

      expect(
        response.toString().trim(),
        isNotEmpty,
        reason: 'Model returned an empty response',
      );
    });

    test('think tags are absent from the ChatController message text', () async {
      _skipIfUnconfigured(config);

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ChatController controller = ChatController(
        chatStore: ChatStore(prefs),
        apiClient: OpenAiCompatibleClient(isWebOverride: false),
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      await controller.sendMessage(
        text: 'What is 2 + 2? Answer with just the number.',
        attachments: const <ChatAttachment>[],
        config: config!,
      );

      final ChatMessage? last = controller.currentThread?.messages.last;
      expect(last, isNotNull);
      expect(last!.isError, isFalse, reason: last.text);
      expect(last.text, isNot(contains('<think>')));
      expect(last.text, isNot(contains('</think>')));
      expect(last.text.trim(), isNotEmpty);
    });

    test('streaming think content does not appear in any intermediate message',
        () async {
      _skipIfUnconfigured(config);

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ChatController controller = ChatController(
        chatStore: ChatStore(prefs),
        apiClient: OpenAiCompatibleClient(isWebOverride: false),
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      // Collect every intermediate text value emitted during streaming.
      final List<String> snapshots = <String>[];
      controller.addListener(() {
        final String? text = controller.currentThread?.messages.last.text;
        if (text != null) snapshots.add(text);
      });

      await controller.sendMessage(
        // Explicitly ask a thinking model to reason before answering.
        text: 'Think step by step, then answer: what is 3 * 7?',
        attachments: const <ChatAttachment>[],
        config: config!,
      );

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
      }
    });
  });

  group('Web search (live DuckDuckGo)', () {
    test('returns results for a common query', () async {
      final WebSearchService service = WebSearchService(isWebOverride: false);

      final List<WebSearchResult> results =
          await service.search('flutter dart programming');

      expect(results, isNotEmpty, reason: 'DuckDuckGo returned no results');
      expect(results.first.title, isNotEmpty);
      expect(results.first.url, startsWith('http'));
      expect(results.first.snippet, isNotEmpty);
    });

    test('does not return raw cookie-consent or privacy-policy pages', () async {
      final WebSearchService service = WebSearchService(isWebOverride: false);

      final List<WebSearchResult> results =
          await service.search('latest technology news today');

      expect(results, isNotEmpty);
      for (final WebSearchResult r in results) {
        expect(
          r.snippet.toLowerCase(),
          isNot(contains('cookie consent')),
          reason: 'Cookie-wall snippet leaked into result: ${r.snippet}',
        );
        expect(
          r.snippet.toLowerCase(),
          isNot(contains('privacy policy')),
          reason: 'Privacy-policy snippet leaked into result: ${r.snippet}',
        );
      }
    });
  });

  group('Web page browse (live)', () {
    test('extracts readable content from a non-paywalled page', () async {
      final WebPageBrowseService browser =
          WebPageBrowseService(isWebOverride: false);

      const WebSearchResult fakeResult = WebSearchResult(
        title: 'Flutter docs',
        url: 'https://docs.flutter.dev/get-started/install',
        snippet: 'Get started with Flutter',
        source: 'manual',
      );

      final List<WebPageExcerpt> excerpts = await browser.browse(
        <WebSearchResult>[fakeResult],
        query: 'flutter install',
        maxPages: 1,
      );

      expect(excerpts, isNotEmpty, reason: 'Browse returned no excerpts');
      final String text = excerpts.first.excerpt;
      expect(text.length, greaterThan(100));
      // Should contain actual content, not a cookie banner.
      expect(
        text.toLowerCase(),
        isNot(contains('cookie consent')),
        reason: 'Browse returned cookie-wall content',
      );
      expect(
        text.toLowerCase(),
        isNot(contains('accept all cookies')),
        reason: 'Browse returned cookie-wall content',
      );
    });

    test('formats browse context with source citations for the LLM', () async {
      final WebPageBrowseService browser =
          WebPageBrowseService(isWebOverride: false);

      const WebSearchResult fakeResult = WebSearchResult(
        title: 'Example Domain',
        url: 'https://example.com',
        snippet: 'Example domain for documentation examples',
        source: 'manual',
      );

      final List<WebSearchResult> results = <WebSearchResult>[fakeResult];
      final List<WebPageExcerpt> excerpts = await browser.browse(
        results,
        query: 'example domain',
        maxPages: 1,
      );

      final String context =
          browser.formatBrowseContext('example domain', results, excerpts);

      expect(context, contains('Sources:'));
      expect(context, contains('example.com'));
    });
  });

  group('Full web-search-to-answer flow', () {
    test('ChatController with useWebSearch injects sources onto the message',
        () async {
      _skipIfUnconfigured(config);

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ChatController controller = ChatController(
        chatStore: ChatStore(prefs),
        apiClient: OpenAiCompatibleClient(isWebOverride: false),
        webSearchService: WebSearchService(isWebOverride: false),
        webPageBrowseService: WebPageBrowseService(isWebOverride: false),
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      await controller.sendMessage(
        text: 'What is the official Flutter website URL?',
        attachments: const <ChatAttachment>[],
        config: config!,
        useWebSearch: true,
      );

      final ChatMessage? last = controller.currentThread?.messages.last;
      expect(last, isNotNull);
      expect(last!.isError, isFalse, reason: last.text);
      expect(last.text, isNot(contains('</think>')));
      // At least one source URL should be attached.
      expect(
        last.sources,
        isNotEmpty,
        reason: 'Expected web sources to be attached to the message',
      );
    });
  });
}
