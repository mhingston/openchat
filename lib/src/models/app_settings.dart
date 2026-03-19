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
    this.jinaApiKey = '',
    this.tavilyApiKey = '',
    this.firecrawlApiKey = '',
    this.braveSearchApiKey = '',
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
      jinaApiKey: json['jinaApiKey'] as String? ?? '',
      tavilyApiKey: json['tavilyApiKey'] as String? ?? '',
      firecrawlApiKey: json['firecrawlApiKey'] as String? ?? '',
      braveSearchApiKey: json['braveSearchApiKey'] as String? ?? '',
    );
  }

  final ThemeMode themeMode;
  final String cachedProviderKey;
  final List<String> cachedModels;
  final String jinaApiKey;
  final String tavilyApiKey;
  final String firecrawlApiKey;
  final String braveSearchApiKey;

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? cachedProviderKey,
    List<String>? cachedModels,
    String? jinaApiKey,
    String? tavilyApiKey,
    String? firecrawlApiKey,
    String? braveSearchApiKey,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      cachedProviderKey: cachedProviderKey ?? this.cachedProviderKey,
      cachedModels: cachedModels ?? this.cachedModels,
      jinaApiKey: jinaApiKey ?? this.jinaApiKey,
      tavilyApiKey: tavilyApiKey ?? this.tavilyApiKey,
      firecrawlApiKey: firecrawlApiKey ?? this.firecrawlApiKey,
      braveSearchApiKey: braveSearchApiKey ?? this.braveSearchApiKey,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'themeMode': themeMode.name,
      'cachedProviderKey': cachedProviderKey,
      'cachedModels': cachedModels,
      'jinaApiKey': jinaApiKey,
      'tavilyApiKey': tavilyApiKey,
      'firecrawlApiKey': firecrawlApiKey,
      'braveSearchApiKey': braveSearchApiKey,
    };
  }
}
