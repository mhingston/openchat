import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app.dart';
import 'src/controllers/chat_controller.dart';
import 'src/controllers/settings_controller.dart';
import 'src/services/app_settings_store.dart';
import 'src/services/chat_store.dart';
import 'src/services/openai_compatible_client.dart';
import 'src/services/prompt_template_store.dart';
import 'src/services/provider_config_store.dart';
import 'src/services/request_foreground_service.dart';
import 'src/services/voice_input_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  RequestForegroundService.init();

  final SharedPreferences preferences = await SharedPreferences.getInstance();
  final ProviderConfigStore providerConfigStore =
      ProviderConfigStore(preferences);
  final AppSettingsStore appSettingsStore = AppSettingsStore(preferences);
  final ChatStore chatStore = ChatStore(preferences);
  final PromptTemplateStore promptTemplateStore =
      PromptTemplateStore(preferences);

  final SettingsController settingsController = SettingsController(
    providerConfigStore: providerConfigStore,
    appSettingsStore: appSettingsStore,
  );
  await settingsController.initialize();

  final ChatController chatController = ChatController(
    chatStore: chatStore,
    apiClient: OpenAiCompatibleClient(),
    promptTemplateStore: promptTemplateStore,
  );
  await chatController.initialize();

  chatController.configureWebSearch(
    jinaApiKey: settingsController.jinaApiKey,
    tavilyApiKey: settingsController.tavilyApiKey,
    firecrawlApiKey: settingsController.firecrawlApiKey,
    braveSearchApiKey: settingsController.braveSearchApiKey,
  );

  runApp(
    MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<SettingsController>.value(
            value: settingsController),
        ChangeNotifierProvider<ChatController>.value(value: chatController),
        ChangeNotifierProvider<VoiceInputService>(
          create: (_) => VoiceInputService(),
        ),
      ],
      child: const OpenChatApp(),
    ),
  );
}
