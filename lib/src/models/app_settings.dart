import 'package:flutter/material.dart';

ThemeMode themeModeFromValue(String value) {
  switch (value) {
    case 'light':
      return ThemeMode.light;
    case 'system':
      return ThemeMode.system;
    case 'dark':
    default:
      return ThemeMode.dark;
  }
}

class AppSettings {
  const AppSettings({
    required this.themeMode,
    required this.cachedProviderKey,
    required this.cachedModels,
  });

  factory AppSettings.initial() {
    return const AppSettings(
      themeMode: ThemeMode.system,
      cachedProviderKey: '',
      cachedModels: <String>[],
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawCachedModels =
        json['cachedModels'] as List<dynamic>? ?? <dynamic>[];
    return AppSettings(
      themeMode: themeModeFromValue(json['themeMode'] as String? ?? 'system'),
      cachedProviderKey: json['cachedProviderKey'] as String? ?? '',
      cachedModels: rawCachedModels.whereType<String>().toList(),
    );
  }

  final ThemeMode themeMode;
  final String cachedProviderKey;
  final List<String> cachedModels;

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? cachedProviderKey,
    List<String>? cachedModels,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      cachedProviderKey: cachedProviderKey ?? this.cachedProviderKey,
      cachedModels: cachedModels ?? this.cachedModels,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'themeMode': themeMode.name,
      'cachedProviderKey': cachedProviderKey,
      'cachedModels': cachedModels,
    };
  }
}
