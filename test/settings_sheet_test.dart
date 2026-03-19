import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openchat/src/controllers/settings_controller.dart';
import 'package:openchat/src/models/provider_config.dart';
import 'package:openchat/src/services/app_settings_store.dart';
import 'package:openchat/src/services/openai_compatible_client.dart';
import 'package:openchat/src/services/provider_config_store.dart';
import 'package:openchat/src/theme/app_theme.dart';
import 'package:openchat/src/widgets/settings_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('API key field can be shown and hidden', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final SettingsController controller = SettingsController(
      providerConfigStore: ProviderConfigStore(preferences),
      appSettingsStore: AppSettingsStore(preferences),
    );
    const ProviderConfig providerConfig = ProviderConfig(
      presetId: 'openai',
      label: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      apiKey: 'sk-test-secret',
      model: 'gpt-4o-mini',
      systemPrompt: '',
      temperature: 1.0,
      streamResponses: true,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsController>.value(
        value: controller,
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Scaffold(
            body: SettingsSheet(
              providerConfig: providerConfig,
              themeMode: ThemeMode.light,
              onSave: (ProviderConfig _, ThemeMode __) async {},
              jinaApiKey: '',
              tavilyApiKey: '',
              firecrawlApiKey: '',
              braveSearchApiKey: '',
              onSaveWebSearch: (String _, String __, String ___, String ____) async {},
            ),
          ),
        ),
      ),
    );

    TextField apiKeyField() {
      return tester.widgetList<TextField>(find.byType(TextField)).firstWhere(
            (TextField field) =>
                field.controller?.text == providerConfig.apiKey,
          );
    }

    expect(apiKeyField().obscureText, isTrue);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();

    expect(apiKeyField().obscureText, isFalse);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pump();

    expect(apiKeyField().obscureText, isTrue);
  });

  testWidgets('Save blocks incomplete chat configuration with a local error', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final SettingsController controller = SettingsController(
      providerConfigStore: ProviderConfigStore(preferences),
      appSettingsStore: AppSettingsStore(preferences),
    );
    bool saved = false;

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsController>.value(
        value: controller,
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Scaffold(
            body: SettingsSheet(
              providerConfig: const ProviderConfig(
                presetId: 'openai',
                label: 'OpenAI',
                baseUrl: 'https://api.openai.com/v1',
                apiKey: 'sk-test-secret',
                model: '',
                systemPrompt: '',
                temperature: 1.0,
                streamResponses: true,
              ),
              themeMode: ThemeMode.light,
              onSave: (ProviderConfig _, ThemeMode __) async {
                saved = true;
              },
              jinaApiKey: '',
              tavilyApiKey: '',
              firecrawlApiKey: '',
              braveSearchApiKey: '',
              onSaveWebSearch: (String _, String __, String ___, String ____) async {},
            ),
          ),
        ),
      ),
    );

    final Finder saveButton =
        find.widgetWithText(FilledButton, 'Save settings');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();

    expect(saved, isFalse);
    expect(
      find.text('Choose or enter a model before saving settings.'),
      findsOneWidget,
    );
  });

  testWidgets('Fetched model result resets after provider details change', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final SettingsController controller = SettingsController(
      providerConfigStore: ProviderConfigStore(preferences),
      appSettingsStore: AppSettingsStore(preferences),
      clientFactory: () => OpenAiCompatibleClient(
        isWebOverride: false,
        httpClient: MockClient((http.Request _) async {
          return http.Response(
            jsonEncode(<String, Object>{
              'data': <Map<String, String>>[
                <String, String>{'id': 'gpt-4o-mini'},
              ],
            }),
            200,
          );
        }),
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsController>.value(
        value: controller,
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Scaffold(
            body: SettingsSheet(
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
              themeMode: ThemeMode.light,
              onSave: (ProviderConfig _, ThemeMode __) async {},
              jinaApiKey: '',
              tavilyApiKey: '',
              firecrawlApiKey: '',
              braveSearchApiKey: '',
              onSaveWebSearch: (String _, String __, String ___, String ____) async {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Connect and fetch models'),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Connection successful. Found 1 model.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'Model name'), findsOneWidget);

    final Finder baseUrlField = find.byWidgetPredicate((Widget widget) {
      return widget is TextField && widget.decoration?.labelText == 'Base URL';
    });

    await tester.enterText(baseUrlField, 'https://api.openai.com/alt/v1');
    await tester.pump();

    expect(
      find.text('Connection successful. Found 1 model.'),
      findsNothing,
    );
  });
}
