import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/provider_config.dart';
import '../services/app_settings_store.dart';
import '../services/openai_compatible_client.dart';
import '../services/provider_config_store.dart';

class SettingsController extends ChangeNotifier {
  SettingsController({
    required ProviderConfigStore providerConfigStore,
    required AppSettingsStore appSettingsStore,
    OpenAiCompatibleClient Function()? clientFactory,
  })  : _providerConfigStore = providerConfigStore,
        _appSettingsStore = appSettingsStore,
        _clientFactory = clientFactory ?? OpenAiCompatibleClient.new;

  final ProviderConfigStore _providerConfigStore;
  final AppSettingsStore _appSettingsStore;
  final OpenAiCompatibleClient Function() _clientFactory;

  ProviderConfig _providerConfig = ProviderConfig.initial();
  AppSettings _appSettings = AppSettings.initial();
  List<String> _availableModels = <String>[];
  bool _initialized = false;

  ProviderConfig get providerConfig => _providerConfig;
  ThemeMode get themeMode => _appSettings.themeMode;
  String get jinaApiKey => _appSettings.jinaApiKey;
  String get tavilyApiKey => _appSettings.tavilyApiKey;
  String get firecrawlApiKey => _appSettings.firecrawlApiKey;
  String get braveSearchApiKey => _appSettings.braveSearchApiKey;
  bool get initialized => _initialized;
  bool get hasConfiguredProvider => _providerConfig.isValidForChat;
  List<String> get availableModels =>
      List<String>.unmodifiable(_availableModels);

  Future<void> initialize() async {
    _providerConfig = await _providerConfigStore.load();
    _appSettings = await _appSettingsStore.load();
    _availableModels =
        _appSettings.cachedProviderKey == _providerConfig.cacheKey
            ? List<String>.from(_appSettings.cachedModels)
            : <String>[];
    _initialized = true;
    notifyListeners();
  }

  Future<void> saveConfiguration({
    required ProviderConfig providerConfig,
    required ThemeMode themeMode,
    String? jinaApiKey,
    String? tavilyApiKey,
    String? firecrawlApiKey,
    String? braveSearchApiKey,
  }) async {
    final bool providerChanged =
        providerConfig.cacheKey != _providerConfig.cacheKey;
    _providerConfig = providerConfig;
    if (providerChanged) {
      _availableModels = <String>[];
    }
    _appSettings = _appSettings.copyWith(
      themeMode: themeMode,
      cachedProviderKey: _providerConfig.cacheKey,
      cachedModels: List<String>.from(_availableModels),
      jinaApiKey: jinaApiKey,
      tavilyApiKey: tavilyApiKey,
      firecrawlApiKey: firecrawlApiKey,
      braveSearchApiKey: braveSearchApiKey,
    );
    await _providerConfigStore.save(providerConfig);
    await _appSettingsStore.save(_appSettings);
    notifyListeners();
  }

  Future<List<String>> fetchModels(ProviderConfig providerConfig) async {
    final List<String> models = await _listModels(providerConfig);
    _availableModels = models;
    _appSettings = _appSettings.copyWith(
      cachedProviderKey: providerConfig.cacheKey,
      cachedModels: List<String>.from(models),
    );
    await _appSettingsStore.save(_appSettings);
    notifyListeners();
    return models;
  }

  Future<List<String>> _listModels(ProviderConfig providerConfig) async {
    final OpenAiCompatibleClient client = _clientFactory();
    try {
      return await client.listModels(config: providerConfig);
    } finally {
      client.dispose();
    }
  }

  void clearAvailableModels() {
    if (_availableModels.isEmpty) {
      return;
    }

    _availableModels = <String>[];
    _appSettings = _appSettings.copyWith(
      cachedProviderKey: '',
      cachedModels: <String>[],
    );
    _appSettingsStore.save(_appSettings);
    notifyListeners();
  }
}
