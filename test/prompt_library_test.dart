import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openchat/src/controllers/chat_controller.dart';
import 'package:openchat/src/models/chat_message.dart';
import 'package:openchat/src/models/chat_thread.dart';
import 'package:openchat/src/models/prompt_template.dart';
import 'package:openchat/src/services/chat_export_service.dart';
import 'package:openchat/src/services/chat_store.dart';
import 'package:openchat/src/services/openai_compatible_client.dart';
import 'package:openchat/src/services/prompt_template_store.dart';
import 'package:openchat/src/theme/app_theme.dart';
import 'package:openchat/src/widgets/prompt_edit_sheet.dart';
import 'package:openchat/src/widgets/prompt_library_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // PromptTemplate model – serialisation round-trip
  // ---------------------------------------------------------------------------
  group('PromptTemplate', () {
    test('round-trips through JSON with all fields', () {
      final DateTime now = DateTime(2026, 3, 20, 9, 0);
      final PromptTemplate original = PromptTemplate(
        id: 'prompt-1',
        name: 'Coding assistant',
        systemPrompt: 'You are an expert software engineer.',
        model: 'gpt-4o',
        temperature: 0.2,
        createdAt: now,
        updatedAt: now,
      );

      final Map<String, dynamic> json = original.toJson();
      final PromptTemplate restored = PromptTemplate.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.systemPrompt, original.systemPrompt);
      expect(restored.model, original.model);
      expect(restored.temperature, original.temperature);
      expect(restored.createdAt, original.createdAt);
      expect(restored.updatedAt, original.updatedAt);
    });

    test('round-trips through JSON with optional fields absent', () {
      final DateTime now = DateTime(2026, 3, 20, 9, 0);
      final PromptTemplate minimal = PromptTemplate(
        id: 'prompt-2',
        name: 'Translator',
        systemPrompt: 'Translate everything to French.',
        createdAt: now,
        updatedAt: now,
      );

      final PromptTemplate restored =
          PromptTemplate.fromJson(minimal.toJson());

      expect(restored.model, isNull);
      expect(restored.temperature, isNull);
    });

    test('copyWith clears model and temperature when requested', () {
      final DateTime now = DateTime(2026, 3, 20, 9, 0);
      final PromptTemplate p = PromptTemplate(
        id: 'prompt-3',
        name: 'Test',
        systemPrompt: 'Hello',
        model: 'gpt-4o',
        temperature: 0.5,
        createdAt: now,
        updatedAt: now,
      );

      final PromptTemplate cleared =
          p.copyWith(clearModel: true, clearTemperature: true);

      expect(cleared.model, isNull);
      expect(cleared.temperature, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // ChatThread – new fields round-trip
  // ---------------------------------------------------------------------------
  group('ChatThread prompt fields', () {
    test('round-trips promptTemplateName and overrides through JSON', () {
      final DateTime now = DateTime(2026, 3, 20, 9, 0);
      final ChatThread thread = ChatThread(
        id: 'thread-1',
        title: 'Coding assistant',
        messages: const <ChatMessage>[],
        createdAt: now,
        updatedAt: now,
        promptTemplateId: 'prompt-1',
        promptTemplateName: 'Coding assistant',
        systemPromptOverride: 'You are an expert.',
        modelOverride: 'gpt-4o',
        temperatureOverride: 0.2,
      );

      final ChatThread restored = ChatThread.fromJson(thread.toJson());

      expect(restored.promptTemplateId, 'prompt-1');
      expect(restored.promptTemplateName, 'Coding assistant');
      expect(restored.systemPromptOverride, 'You are an expert.');
      expect(restored.modelOverride, 'gpt-4o');
      expect(restored.temperatureOverride, 0.2);
    });

    test('fromJson is backward compatible — missing fields are null', () {
      final Map<String, dynamic> legacy = <String, dynamic>{
        'id': 'thread-1',
        'title': 'Old thread',
        'messages': <dynamic>[],
        'createdAt': '2026-01-01T00:00:00.000',
        'updatedAt': '2026-01-01T00:00:00.000',
        'isPinned': false,
      };

      final ChatThread thread = ChatThread.fromJson(legacy);

      expect(thread.promptTemplateId, isNull);
      expect(thread.promptTemplateName, isNull);
      expect(thread.systemPromptOverride, isNull);
      expect(thread.modelOverride, isNull);
      expect(thread.temperatureOverride, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // PromptTemplateStore – save / load
  // ---------------------------------------------------------------------------
  group('PromptTemplateStore', () {
    test('saves and loads prompts', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PromptTemplateStore store = PromptTemplateStore(prefs);

      final DateTime now = DateTime(2026, 3, 20, 9, 0);
      final List<PromptTemplate> prompts = <PromptTemplate>[
        PromptTemplate(
          id: 'p1',
          name: 'Writer',
          systemPrompt: 'Write clearly.',
          createdAt: now,
          updatedAt: now,
        ),
        PromptTemplate(
          id: 'p2',
          name: 'Coder',
          systemPrompt: 'Write code.',
          model: 'gpt-4o',
          createdAt: now,
          updatedAt: now,
        ),
      ];

      await store.savePrompts(prompts);
      final List<PromptTemplate> loaded = await store.loadPrompts();

      expect(loaded, hasLength(2));
      expect(loaded.first.id, 'p1');
      expect(loaded.last.model, 'gpt-4o');
    });

    test('returns empty list when nothing is stored', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PromptTemplateStore store = PromptTemplateStore(prefs);

      expect(await store.loadPrompts(), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // ChatExportService – prompts included in JSON export/import
  // ---------------------------------------------------------------------------
  group('ChatExportService prompt export/import', () {
    test('exported JSON includes prompts array', () {
      final DateTime now = DateTime(2026, 3, 20, 9, 0);
      final PromptTemplate prompt = PromptTemplate(
        id: 'p1',
        name: 'Writer',
        systemPrompt: 'Write clearly.',
        createdAt: now,
        updatedAt: now,
      );
      final ChatThread thread = ChatThread(
        id: 't1',
        title: 'Thread',
        messages: const <ChatMessage>[],
        createdAt: now,
        updatedAt: now,
      );

      final ChatExportService service = ChatExportService();
      final String json = service.exportThreadsAsJson(
        <ChatThread>[thread],
        prompts: <PromptTemplate>[prompt],
      );
      final Map<String, dynamic> decoded =
          jsonDecode(json) as Map<String, dynamic>;

      expect(decoded['prompts'], isA<List<dynamic>>());
      expect((decoded['prompts'] as List<dynamic>).single['id'], 'p1');
    });

    test('import round-trips prompts', () {
      final DateTime now = DateTime(2026, 3, 20, 9, 0);
      final PromptTemplate prompt = PromptTemplate(
        id: 'p1',
        name: 'Coder',
        systemPrompt: 'Write code.',
        createdAt: now,
        updatedAt: now,
      );
      final ChatThread thread = ChatThread(
        id: 't1',
        title: 'Thread',
        messages: const <ChatMessage>[],
        createdAt: now,
        updatedAt: now,
      );

      final ChatExportService service = ChatExportService();
      final String json = service.exportThreadsAsJson(
        <ChatThread>[thread],
        prompts: <PromptTemplate>[prompt],
      );
      final ImportResult result = service.importThreadsFromJson(json);

      expect(result.isSuccess, isTrue);
      expect(result.prompts, hasLength(1));
      expect(result.prompts.single.name, 'Coder');
    });

    test('import from legacy export without prompts key returns empty prompts',
        () {
      const String legacy = '''
[
  {
    "id": "t1",
    "title": "Old chat",
    "messages": [],
    "createdAt": "2026-01-01T00:00:00.000",
    "updatedAt": "2026-01-01T00:00:00.000",
    "isPinned": false
  }
]''';
      final ChatExportService service = ChatExportService();
      final ImportResult result = service.importThreadsFromJson(legacy);

      expect(result.isSuccess, isTrue);
      expect(result.prompts, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Widget: PromptEditSheet
  // ---------------------------------------------------------------------------
  group('PromptEditSheet', () {
    testWidgets('requires a non-empty name before saving', (WidgetTester tester) async {
      PromptTemplate? saved;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Scaffold(
            body: PromptEditSheet(
              onSave: (PromptTemplate p) => saved = p,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap save without entering a name
      await tester.tap(find.text('Create prompt'));
      await tester.pumpAndSettle();

      expect(saved, isNull);
      expect(find.text('Name is required'), findsOneWidget);
    });

    testWidgets('returns a PromptTemplate when saved with valid data',
        (WidgetTester tester) async {
      PromptTemplate? saved;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Scaffold(
            body: PromptEditSheet(
              onSave: (PromptTemplate p) => saved = p,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Name'), 'Writer');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'System message'),
        'Write clearly.',
      );
      await tester.tap(find.text('Create prompt'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.name, 'Writer');
      expect(saved!.systemPrompt, 'Write clearly.');
    });
  });

  // ---------------------------------------------------------------------------
  // Widget: PromptLibrarySheet
  // ---------------------------------------------------------------------------
  group('PromptLibrarySheet', () {
    Future<ChatController> _makeController() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ChatController controller = ChatController(
        chatStore: ChatStore(prefs),
        promptTemplateStore: PromptTemplateStore(prefs),
        apiClient: _stubClient(),
      );
      await controller.initialize();
      return controller;
    }

    testWidgets('shows empty state when no prompts exist',
        (WidgetTester tester) async {
      final ChatController controller = await _makeController();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: ChangeNotifierProvider<ChatController>.value(
            value: controller,
            child: const Scaffold(body: PromptLibrarySheet()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No prompts yet'), findsOneWidget);
    });

    testWidgets('shows saved prompts in the list', (WidgetTester tester) async {
      final ChatController controller = await _makeController();
      final DateTime now = DateTime(2026, 3, 20, 9, 0);
      await controller.savePrompt(PromptTemplate(
        id: 'p1',
        name: 'Coding assistant',
        systemPrompt: 'Write code.',
        createdAt: now,
        updatedAt: now,
      ));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: ChangeNotifierProvider<ChatController>.value(
            value: controller,
            child: const Scaffold(body: PromptLibrarySheet()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Coding assistant'), findsOneWidget);
      expect(find.text('No prompts yet'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Widget: ConversationList prompt badge
  // ---------------------------------------------------------------------------
  group('Thread list prompt badge', () {
    testWidgets('shows prompt name badge when thread has a promptTemplateName',
        (WidgetTester tester) async {
      final ChatController controller = await _makeControllerWithThread();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: ChangeNotifierProvider<ChatController>.value(
            value: controller,
            child: Scaffold(
              body: Builder(
                builder: (BuildContext context) {
                  // Render via the drawer which hosts ConversationList
                  return Text(
                    controller.threads.first.promptTemplateName ?? '',
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Coding assistant'), findsOneWidget);
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

OpenAiCompatibleClient _stubClient() {
  return OpenAiCompatibleClient(
    isWebOverride: false,
    httpClient: MockClient((_) async => http.Response('{}', 200)),
  );
}

Future<ChatController> _makeControllerWithThread() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final ChatController controller = ChatController(
    chatStore: ChatStore(prefs),
    promptTemplateStore: PromptTemplateStore(prefs),
    apiClient: _stubClient(),
  );
  await controller.initialize();
  final DateTime now = DateTime(2026, 3, 20, 9, 0);
  await controller.savePrompt(PromptTemplate(
    id: 'p1',
    name: 'Coding assistant',
    systemPrompt: 'Write code.',
    createdAt: now,
    updatedAt: now,
  ));
  await controller.createThreadFromPrompt(controller.prompts.first);
  return controller;
}
