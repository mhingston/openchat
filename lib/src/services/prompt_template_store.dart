import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/prompt_template.dart';

class PromptTemplateStore {
  PromptTemplateStore(this._preferences);

  static const String _storageKey = 'openchat.promptTemplates';

  final SharedPreferences _preferences;

  Future<List<PromptTemplate>> loadPrompts() async {
    final String? rawValue = _preferences.getString(_storageKey);
    if (rawValue == null || rawValue.isEmpty) {
      return <PromptTemplate>[];
    }

    final Object? decoded = jsonDecode(rawValue);
    if (decoded is! List<dynamic>) {
      return <PromptTemplate>[];
    }

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(PromptTemplate.fromJson)
        .toList();
  }

  Future<void> savePrompts(List<PromptTemplate> prompts) async {
    final List<Map<String, dynamic>> serialized =
        prompts.map((PromptTemplate p) => p.toJson()).toList();
    await _preferences.setString(_storageKey, jsonEncode(serialized));
  }
}
