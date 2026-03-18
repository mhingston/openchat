import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

class AppSettingsStore {
  AppSettingsStore(this._preferences);

  static const String _storageKey = 'openchat.appSettings';

  final SharedPreferences _preferences;

  Future<AppSettings> load() async {
    final String? rawValue = _preferences.getString(_storageKey);
    if (rawValue == null || rawValue.isEmpty) {
      return AppSettings.initial();
    }

    final Object? decoded = jsonDecode(rawValue);
    if (decoded is! Map<String, dynamic>) {
      return AppSettings.initial();
    }

    return AppSettings.fromJson(decoded);
  }

  Future<void> save(AppSettings settings) async {
    await _preferences.setString(_storageKey, jsonEncode(settings.toJson()));
  }
}
