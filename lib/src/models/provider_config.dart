class ProviderPreset {
  const ProviderPreset({
    required this.id,
    required this.name,
    required this.defaultLabel,
    required this.defaultBaseUrl,
    required this.modelHint,
    required this.helperText,
    required this.apiKeyRequired,
    required this.apiStyle,
  });

  final String id;
  final String name;
  final String defaultLabel;
  final String defaultBaseUrl;
  final String modelHint;
  final String helperText;
  final bool apiKeyRequired;
  final ProviderApiStyle apiStyle;
}

enum ProviderApiStyle { openAi, ollama, anthropic, openCodeGo }

const List<ProviderPreset> providerPresets = <ProviderPreset>[
  ProviderPreset(
    id: 'custom',
    name: 'Custom OpenAI-compatible',
    defaultLabel: 'Custom provider',
    defaultBaseUrl: '',
    modelHint: 'gpt-4o-mini',
    helperText: 'Use any OpenAI-compatible endpoint that exposes /v1.',
    apiKeyRequired: false,
    apiStyle: ProviderApiStyle.openAi,
  ),
  ProviderPreset(
    id: 'custom-anthropic',
    name: 'Custom Anthropic-compatible',
    defaultLabel: 'Custom Anthropic provider',
    defaultBaseUrl: '',
    modelHint: 'claude-3-5-sonnet-20241022',
    helperText:
        'Use any Anthropic-compatible endpoint that exposes /v1/messages.',
    apiKeyRequired: false,
    apiStyle: ProviderApiStyle.anthropic,
  ),
  ProviderPreset(
    id: 'anthropic',
    name: 'Anthropic',
    defaultLabel: 'Anthropic',
    defaultBaseUrl: 'https://api.anthropic.com/v1',
    modelHint: 'claude-3-5-sonnet-20241022',
    helperText: 'Official Anthropic API (Claude models).',
    apiKeyRequired: true,
    apiStyle: ProviderApiStyle.anthropic,
  ),
  ProviderPreset(
    id: 'opencode-go',
    name: 'OpenCode Go',
    defaultLabel: 'OpenCode Go',
    defaultBaseUrl: 'https://opencode.ai/zen/go/v1',
    modelHint: 'glm-5',
    helperText:
        'OpenCode Go subscription — all models. MiniMax models are routed automatically.',
    apiKeyRequired: true,
    apiStyle: ProviderApiStyle.openCodeGo,
  ),
  ProviderPreset(
    id: 'openai',
    name: 'OpenAI',
    defaultLabel: 'OpenAI',
    defaultBaseUrl: 'https://api.openai.com/v1',
    modelHint: 'gpt-4o-mini',
    helperText: 'Best for the standard OpenAI API.',
    apiKeyRequired: true,
    apiStyle: ProviderApiStyle.openAi,
  ),
  ProviderPreset(
    id: 'openrouter',
    name: 'OpenRouter',
    defaultLabel: 'OpenRouter',
    defaultBaseUrl: 'https://openrouter.ai/api/v1',
    modelHint: 'openai/gpt-4o-mini',
    helperText: 'Route requests across multiple providers with one API.',
    apiKeyRequired: true,
    apiStyle: ProviderApiStyle.openAi,
  ),
  ProviderPreset(
    id: 'groq',
    name: 'Groq',
    defaultLabel: 'Groq',
    defaultBaseUrl: 'https://api.groq.com/openai/v1',
    modelHint: 'llama-3.3-70b-versatile',
    helperText: 'Fast OpenAI-compatible inference from Groq.',
    apiKeyRequired: true,
    apiStyle: ProviderApiStyle.openAi,
  ),
  ProviderPreset(
    id: 'together',
    name: 'Together AI',
    defaultLabel: 'Together AI',
    defaultBaseUrl: 'https://api.together.xyz/v1',
    modelHint: 'meta-llama/Llama-3.3-70B-Instruct-Turbo',
    helperText: 'Hosted open models through an OpenAI-compatible API.',
    apiKeyRequired: true,
    apiStyle: ProviderApiStyle.openAi,
  ),
  ProviderPreset(
    id: 'deepseek',
    name: 'DeepSeek',
    defaultLabel: 'DeepSeek',
    defaultBaseUrl: 'https://api.deepseek.com/v1',
    modelHint: 'deepseek-chat',
    helperText: 'DeepSeek chat and reasoning models via /v1.',
    apiKeyRequired: true,
    apiStyle: ProviderApiStyle.openAi,
  ),
  ProviderPreset(
    id: 'ollama-cloud',
    name: 'Ollama Cloud',
    defaultLabel: 'Ollama Cloud',
    defaultBaseUrl: 'https://ollama.com',
    modelHint: 'gpt-oss:120b',
    helperText: 'Ollama Cloud API on ollama.com.',
    apiKeyRequired: true,
    apiStyle: ProviderApiStyle.ollama,
  ),
];

ProviderPreset providerPresetById(String id) {
  for (final ProviderPreset preset in providerPresets) {
    if (preset.id == id) {
      return preset;
    }
  }

  return providerPresets.first;
}

class ProviderConfig {
  const ProviderConfig({
    required this.presetId,
    required this.label,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.systemPrompt,
    required this.temperature,
    required this.streamResponses,
  });

  factory ProviderConfig.initial() {
    return const ProviderConfig(
      presetId: 'openai',
      label: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      apiKey: '',
      model: '',
      systemPrompt: '',
      temperature: 1.0,
      streamResponses: true,
    );
  }

  factory ProviderConfig.fromJson(Map<String, dynamic> json) {
    final String presetId = json['presetId'] as String? ?? 'openai';
    final ProviderPreset preset = providerPresetById(presetId);
    return ProviderConfig(
      presetId: presetId,
      label: json['label'] as String? ?? preset.defaultLabel,
      baseUrl: json['baseUrl'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      model: json['model'] as String? ?? '',
      systemPrompt: json['systemPrompt'] as String? ?? '',
      temperature: (json['temperature'] as num?)?.toDouble() ?? 1.0,
      streamResponses: json['streamResponses'] as bool? ?? true,
    );
  }

  final String presetId;
  final String label;
  final String baseUrl;
  final String apiKey;
  final String model;
  final String systemPrompt;
  final double temperature;
  final bool streamResponses;

  static String normalizeOpenAiBaseUrl(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final String withoutEndpoint = trimmed.replaceFirst(
      RegExp(r'/(chat/completions|models)/?$'),
      '',
    );
    final String withoutTrailingSlash = withoutEndpoint.replaceAll(
      RegExp(r'/+$'),
      '',
    );

    if (withoutTrailingSlash.endsWith('/v1')) {
      return withoutTrailingSlash;
    }

    return '$withoutTrailingSlash/v1';
  }

  static String normalizeOllamaBaseUrl(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final String withoutEndpoint = trimmed.replaceFirst(
      RegExp(r'/(api/chat|api/tags|chat/completions|models)/?$'),
      '',
    );
    return withoutEndpoint.replaceAll(RegExp(r'/+$'), '');
  }

  static String normalizeAnthropicBaseUrl(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final String withoutEndpoint = trimmed.replaceFirst(
      RegExp(r'/messages/?$'),
      '',
    );
    final String withoutTrailingSlash = withoutEndpoint.replaceAll(
      RegExp(r'/+$'),
      '',
    );

    if (withoutTrailingSlash.endsWith('/v1')) {
      return withoutTrailingSlash;
    }

    return '$withoutTrailingSlash/v1';
  }

  static String normalizeBaseUrl(
    String value, {
    ProviderApiStyle apiStyle = ProviderApiStyle.openAi,
  }) {
    switch (apiStyle) {
      case ProviderApiStyle.ollama:
        return normalizeOllamaBaseUrl(value);
      case ProviderApiStyle.anthropic:
        return normalizeAnthropicBaseUrl(value);
      case ProviderApiStyle.openAi:
      case ProviderApiStyle.openCodeGo:
        return normalizeOpenAiBaseUrl(value);
    }
  }

  String get normalizedBaseUrl =>
      normalizeBaseUrl(baseUrl, apiStyle: preset.apiStyle);

  ProviderPreset get preset => providerPresetById(presetId);

  bool get requiresApiKey => preset.apiKeyRequired;
  bool get usesOllamaApi => preset.apiStyle == ProviderApiStyle.ollama;
  bool get usesAnthropicApi => preset.apiStyle == ProviderApiStyle.anthropic;
  bool get usesOpenCodeGoApi => preset.apiStyle == ProviderApiStyle.openCodeGo;

  bool get isReadyForConnectionTest {
    return normalizedBaseUrl.isNotEmpty &&
        (!requiresApiKey || apiKey.trim().isNotEmpty);
  }

  bool get isCompleteForChat {
    return isReadyForConnectionTest && model.trim().isNotEmpty;
  }

  String? get connectionTestValidationMessage {
    if (normalizedBaseUrl.isEmpty) {
      return 'Add a base URL before testing the connection.';
    }
    if (requiresApiKey && apiKey.trim().isEmpty) {
      return 'Add an API key before testing the connection.';
    }
    return null;
  }

  String? get chatValidationMessage {
    if (normalizedBaseUrl.isEmpty) {
      return 'Add a base URL before saving settings.';
    }
    if (requiresApiKey && apiKey.trim().isEmpty) {
      return 'Add an API key before saving settings.';
    }
    if (model.trim().isEmpty) {
      return 'Choose or enter a model before saving settings.';
    }
    return null;
  }

  bool get isValidForChat {
    return isCompleteForChat;
  }

  String get cacheKey => '${preset.id}|$normalizedBaseUrl|${apiKey.trim()}';

  ProviderConfig copyWith({
    String? presetId,
    String? label,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? systemPrompt,
    double? temperature,
    bool? streamResponses,
  }) {
    return ProviderConfig(
      presetId: presetId ?? this.presetId,
      label: label ?? this.label,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      temperature: temperature ?? this.temperature,
      streamResponses: streamResponses ?? this.streamResponses,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'presetId': presetId,
      'label': label,
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'model': model,
      'systemPrompt': systemPrompt,
      'temperature': temperature,
      'streamResponses': streamResponses,
    };
  }
}
