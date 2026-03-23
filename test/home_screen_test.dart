import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openchat/src/controllers/chat_controller.dart';
import 'package:openchat/src/controllers/settings_controller.dart';
import 'package:openchat/src/models/chat_thread.dart';
import 'package:openchat/src/models/provider_config.dart';
import 'package:openchat/src/screens/home_screen.dart';
import 'package:openchat/src/services/app_settings_store.dart';
import 'package:openchat/src/services/chat_store.dart';
import 'package:openchat/src/services/openai_compatible_client.dart';
import 'package:openchat/src/services/prompt_template_store.dart';
import 'package:openchat/src/services/provider_config_store.dart';
import 'package:openchat/src/services/tts_service.dart';
import 'package:openchat/src/services/voice_input_service.dart';
import 'package:openchat/src/theme/app_theme.dart';
import 'package:openchat/src/utils/keyboard_shortcuts.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    OpenChatKeyboardShortcuts.debugIsDesktopOrWebOverride = true;
    OpenChatKeyboardShortcuts.debugIsApplePlatformOverride = true;
  });

  tearDown(() {
    OpenChatKeyboardShortcuts.debugIsDesktopOrWebOverride = null;
    OpenChatKeyboardShortcuts.debugIsApplePlatformOverride = null;
  });

  testWidgets(
      'first run shows provider setup empty state and disabled composer',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    final SettingsController settingsController = SettingsController(
      providerConfigStore: ProviderConfigStore(preferences),
      appSettingsStore: AppSettingsStore(preferences),
    );
    await settingsController.initialize();

    final ChatController chatController = ChatController(
      chatStore: ChatStore(preferences),
      promptTemplateStore: PromptTemplateStore(preferences),
      apiClient: OpenAiCompatibleClient(
        isWebOverride: false,
        httpClient: MockClient((http.Request request) async {
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
    );
    await chatController.initialize();

    await tester.pumpWidget(
      MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<SettingsController>.value(
            value: settingsController,
          ),
          ChangeNotifierProvider<ChatController>.value(value: chatController),
          ChangeNotifierProvider<VoiceInputService>(
            create: (_) => VoiceInputService.withState(
              const VoiceInputState(status: VoiceInputStatus.idle),
            ),
          ),
          ChangeNotifierProvider<TtsService>(create: (_) => TtsService()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          darkTheme: AppTheme.darkTheme(),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Set up a provider to start'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Open settings'), findsOneWidget);
    expect(
      find.text('Set up a provider to unlock the composer'),
      findsNothing,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).first).enabled,
      isFalse,
    );
  });

  testWidgets('desktop shortcuts open search/settings and navigate threads',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    final ChatStore chatStore = ChatStore(preferences);
    await chatStore.saveThreads(<ChatThread>[
      ChatThread(
        id: 'thread-1',
        title: 'First thread',
        messages: const [],
        createdAt: DateTime(2026, 3, 16, 10),
        updatedAt: DateTime(2026, 3, 16, 10),
      ),
      ChatThread(
        id: 'thread-2',
        title: 'Second thread',
        messages: const [],
        createdAt: DateTime(2026, 3, 16, 11),
        updatedAt: DateTime(2026, 3, 16, 11),
      ),
    ]);

    final SettingsController settingsController = SettingsController(
      providerConfigStore: ProviderConfigStore(preferences),
      appSettingsStore: AppSettingsStore(preferences),
    );
    await settingsController.initialize();

    final ChatController chatController = ChatController(
      chatStore: chatStore,
      promptTemplateStore: PromptTemplateStore(preferences),
      apiClient: OpenAiCompatibleClient(
        isWebOverride: false,
        httpClient: MockClient((http.Request request) async {
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
    );
    await chatController.initialize();

    await tester.pumpWidget(
      MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<SettingsController>.value(
            value: settingsController,
          ),
          ChangeNotifierProvider<ChatController>.value(value: chatController),
          ChangeNotifierProvider<VoiceInputService>(
            create: (_) => VoiceInputService.withState(
              const VoiceInputState(status: VoiceInputStatus.idle),
            ),
          ),
          ChangeNotifierProvider<TtsService>(create: (_) => TtsService()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          darkTheme: AppTheme.darkTheme(),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(chatController.currentThread!.id, 'thread-2');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.text('Search conversations'), findsOneWidget);

    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(chatController.currentThread!.id, 'thread-1');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(chatController.threads.length, 3);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.text('Provider setup'), findsOneWidget);
  });

  testWidgets('header shows current-chat export action when a thread exists',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    final ChatStore chatStore = ChatStore(preferences);
    await chatStore.saveThreads(<ChatThread>[
      ChatThread(
        id: 'thread-1',
        title: 'First thread',
        messages: const [],
        createdAt: DateTime(2026, 3, 16, 10),
        updatedAt: DateTime(2026, 3, 16, 10),
      ),
    ]);

    final SettingsController settingsController = SettingsController(
      providerConfigStore: ProviderConfigStore(preferences),
      appSettingsStore: AppSettingsStore(preferences),
    );
    await settingsController.initialize();

    final ChatController chatController = ChatController(
      chatStore: chatStore,
      promptTemplateStore: PromptTemplateStore(preferences),
      apiClient: OpenAiCompatibleClient(
        isWebOverride: false,
        httpClient: MockClient((http.Request request) async {
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
    );
    await chatController.initialize();

    await tester.pumpWidget(
      MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<SettingsController>.value(
            value: settingsController,
          ),
          ChangeNotifierProvider<ChatController>.value(value: chatController),
          ChangeNotifierProvider<VoiceInputService>(
            create: (_) => VoiceInputService.withState(
              const VoiceInputState(status: VoiceInputStatus.idle),
            ),
          ),
          ChangeNotifierProvider<TtsService>(create: (_) => TtsService()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          darkTheme: AppTheme.darkTheme(),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('header-export-current-button')), findsOneWidget);
    expect(find.byTooltip('Export current chat'), findsOneWidget);
  });

  testWidgets('narrow viewport switches header and composer to compact layout',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    final ChatStore chatStore = ChatStore(preferences);
    await chatStore.saveThreads(<ChatThread>[
      ChatThread(
        id: 'thread-1',
        title: 'First thread',
        messages: const [],
        createdAt: DateTime(2026, 3, 16, 10),
        updatedAt: DateTime(2026, 3, 16, 10),
      ),
    ]);

    final SettingsController settingsController = SettingsController(
      providerConfigStore: ProviderConfigStore(preferences),
      appSettingsStore: AppSettingsStore(preferences),
    );
    await settingsController.initialize();
    await settingsController.saveConfiguration(
      providerConfig: const ProviderConfig(
        presetId: 'openai',
        label: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test-secret',
        model: 'gpt-4o-mini',
        systemPrompt: '',
        temperature: 1.0,
        streamResponses: true,
      ),
      themeMode: ThemeMode.dark,
    );

    final ChatController chatController = ChatController(
      chatStore: chatStore,
      promptTemplateStore: PromptTemplateStore(preferences),
      apiClient: OpenAiCompatibleClient(
        isWebOverride: false,
        httpClient: MockClient((http.Request request) async {
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
    );
    await chatController.initialize();

    await tester.pumpWidget(
      MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<SettingsController>.value(
            value: settingsController,
          ),
          ChangeNotifierProvider<ChatController>.value(value: chatController),
          ChangeNotifierProvider<VoiceInputService>(
            create: (_) => VoiceInputService.withState(
              const VoiceInputState(status: VoiceInputStatus.idle),
            ),
          ),
          ChangeNotifierProvider<TtsService>(create: (_) => TtsService()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          darkTheme: AppTheme.darkTheme(),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('openchat-header-compact-actions')),
        findsOneWidget);
    expect(
        find.byKey(const Key('chat-composer-compact-layout')), findsOneWidget);
  });
}
