import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/provider_config.dart';

class ProviderConfigStore {
  ProviderConfigStore(this._preferences);

  static const String _storageKey = 'openchat.providerConfig';

  final SharedPreferences _preferences;

  Future<ProviderConfig> load() async {
    final String? rawValue = _preferences.getString(_storageKey);
    if (rawValue == null || rawValue.isEmpty) {
      return ProviderConfig.initial();
    }

    final Object? decoded = jsonDecode(rawValue);
    if (decoded is! Map<String, dynamic>) {
      return ProviderConfig.initial();
    }

    return ProviderConfig.fromJson(decoded);
  }

  Future<void> save(ProviderConfig config) async {
    await _preferences.setString(_storageKey, jsonEncode(config.toJson()));
  }
}
