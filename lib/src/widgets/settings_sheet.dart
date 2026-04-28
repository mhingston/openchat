import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/settings_controller.dart';
import '../models/provider_config.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';
import 'chat_markdown.dart';

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    required this.providerConfig,
    required this.themeMode,
    required this.onSave,
    required this.jinaApiKey,
    required this.tavilyApiKey,
    required this.firecrawlApiKey,
    required this.braveSearchApiKey,
    required this.exaApiKey,
    required this.deepResearchMaxRounds,
    required this.onSaveWebSearch,
  });

  final ProviderConfig providerConfig;
  final ThemeMode themeMode;
  final Future<void> Function(
      ProviderConfig providerConfig, ThemeMode themeMode) onSave;
  final String jinaApiKey;
  final String tavilyApiKey;
  final String firecrawlApiKey;
  final String braveSearchApiKey;
  final String exaApiKey;
  final int deepResearchMaxRounds;
  final Future<void> Function(
    String jinaApiKey,
    String tavilyApiKey,
    String firecrawlApiKey,
    String braveSearchApiKey,
    String exaApiKey,
    int deepResearchMaxRounds,
  ) onSaveWebSearch;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late final TextEditingController _labelController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  late final TextEditingController _systemPromptController;

  late String _selectedPresetId;
  late double _temperature;
  late bool _streamResponses;
  late ThemeMode _themeMode;
  String? _modelFetchSuccess;
  String? _modelFetchError;
  String? _saveError;
  bool _fetchingModels = false;
  bool _saving = false;
  bool _obscureApiKey = true;
  bool _showSystemPromptPreview = false;
  late final TextEditingController _jinaApiKeyController;
  late final TextEditingController _tavilyApiKeyController;
  late final TextEditingController _firecrawlApiKeyController;
  late final TextEditingController _braveSearchApiKeyController;
  late final TextEditingController _exaApiKeyController;
  bool _obscureJinaApiKey = true;
  bool _obscureTavilyApiKey = true;
  bool _obscureFirecrawlApiKey = true;
  bool _obscureBraveSearchApiKey = true;
  bool _obscureExaApiKey = true;
  late int _deepResearchMaxRounds;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.providerConfig.label);
    _baseUrlController =
        TextEditingController(text: widget.providerConfig.baseUrl);
    _apiKeyController =
        TextEditingController(text: widget.providerConfig.apiKey);
    _modelController = TextEditingController(text: widget.providerConfig.model);
    _systemPromptController =
        TextEditingController(text: widget.providerConfig.systemPrompt);
    _selectedPresetId = widget.providerConfig.presetId;
    _temperature = widget.providerConfig.temperature;
    _streamResponses = widget.providerConfig.streamResponses;
    _themeMode = widget.themeMode;
    _jinaApiKeyController = TextEditingController(text: widget.jinaApiKey);
    _tavilyApiKeyController = TextEditingController(text: widget.tavilyApiKey);
    _firecrawlApiKeyController =
        TextEditingController(text: widget.firecrawlApiKey);
    _braveSearchApiKeyController =
        TextEditingController(text: widget.braveSearchApiKey);
    _exaApiKeyController = TextEditingController(text: widget.exaApiKey);
    _deepResearchMaxRounds = widget.deepResearchMaxRounds;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _systemPromptController.dispose();
    _jinaApiKeyController.dispose();
    _tavilyApiKeyController.dispose();
    _firecrawlApiKeyController.dispose();
    _braveSearchApiKeyController.dispose();
    _exaApiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SettingsController settingsController =
        context.watch<SettingsController>();
    final TtsService ttsService = context.watch<TtsService>();
    final ProviderConfig draftConfig = _draftConfig();
    final ProviderPreset preset = providerPresetById(_selectedPresetId);
    final List<String> availableModels = settingsController.availableModels;
    final String selectedModel = _modelController.text.trim();
    final String? fetchedModelValue =
        availableModels.contains(selectedModel) ? selectedModel : null;
    final bool canFetchModels = draftConfig.isReadyForConnectionTest;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Card(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Provider setup',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.openChatPalette.surfaceRaised,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: context.openChatPalette.border),
                    ),
                    child: Text(
                      'Choose a provider, enter your API details, fetch models, then save. You can still type a model manually if your provider does not list one.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.openChatPalette.mutedText,
                          ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Connection',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedPresetId,
                    decoration: const InputDecoration(labelText: 'Provider'),
                    items: providerPresets
                        .map(
                          (ProviderPreset item) => DropdownMenuItem<String>(
                            value: item.id,
                            child: Text(item.name),
                          ),
                        )
                        .toList(),
                    onChanged: (String? value) {
                      if (value == null || value == _selectedPresetId) {
                        return;
                      }
                      _applyPreset(value);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    preset.helperText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.openChatPalette.mutedText,
                        ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _labelController,
                    decoration:
                        const InputDecoration(labelText: 'Provider label'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _baseUrlController,
                    keyboardType: TextInputType.url,
                    onChanged: (_) => _handleConnectionChanged(),
                    decoration: InputDecoration(
                      labelText: 'Base URL',
                      hintText: preset.defaultBaseUrl.isEmpty
                          ? 'https://api.openai.com/v1'
                          : preset.defaultBaseUrl,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: _obscureApiKey,
                    onChanged: (_) => _handleConnectionChanged(),
                    decoration: InputDecoration(
                      labelText: preset.apiKeyRequired
                          ? 'API key'
                          : 'API key (optional)',
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _obscureApiKey = !_obscureApiKey;
                          });
                        },
                        tooltip:
                            _obscureApiKey ? 'Show API key' : 'Hide API key',
                        icon: Icon(
                          _obscureApiKey
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  if (kIsWeb) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      'On the web preview, OpenChat routes provider requests through the local web proxy. Add any custom hosts to the proxy allowlist if needed.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.openChatPalette.mutedText,
                          ),
                    ),
                    const SizedBox(height: 16),
                  ] else
                    const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: (_fetchingModels || !canFetchModels)
                          ? null
                          : _fetchModels,
                      icon: _fetchingModels
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_outlined),
                      label: Text(
                        _fetchingModels
                            ? 'Fetching models...'
                            : 'Connect and fetch models',
                      ),
                    ),
                  ),
                  if (_modelFetchError != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      _modelFetchError!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                  ] else if (_modelFetchSuccess != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      _modelFetchSuccess!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.openChatPalette.success,
                          ),
                    ),
                  ] else if (availableModels.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      '${availableModels.length} model${availableModels.length == 1 ? '' : 's'} ready to pick.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.openChatPalette.mutedText,
                          ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Model',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  if (availableModels.isNotEmpty) ...<Widget>[
                    DropdownButtonFormField<String>(
                      initialValue: fetchedModelValue,
                      decoration: const InputDecoration(
                        labelText: 'Fetched models',
                      ),
                      hint: const Text('Select a fetched model'),
                      items: availableModels
                          .map(
                            (String model) => DropdownMenuItem<String>(
                              value: model,
                              child: Text(
                                model,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (String? value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _modelController.text = value;
                          _modelFetchSuccess = null;
                          _modelFetchError = null;
                          _saveError = null;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Select a fetched model or enter one manually below.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.openChatPalette.mutedText,
                          ),
                    ),
                    const SizedBox(height: 12),
                  ] else ...<Widget>[
                    Text(
                      'Enter a model manually, or fetch available models after completing your connection details.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.openChatPalette.mutedText,
                          ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _modelController,
                    onChanged: (_) => _handleDraftChanged(),
                    decoration: InputDecoration(
                      labelText: 'Model name',
                      hintText: preset.modelHint,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Text(
                        'System prompt',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: context.openChatPalette.mutedText,
                            ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: _showSystemPromptPreview
                            ? 'Edit system prompt'
                            : 'Preview system prompt',
                        icon: Icon(
                          _showSystemPromptPreview
                              ? Icons.edit_outlined
                              : Icons.preview_outlined,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() {
                            _showSystemPromptPreview =
                                !_showSystemPromptPreview;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (_showSystemPromptPreview &&
                      _systemPromptController.text.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.openChatPalette.surfaceRaised,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.openChatPalette.border),
                      ),
                      child: ChatMarkdown(data: _systemPromptController.text),
                    )
                  else
                    TextField(
                      controller: _systemPromptController,
                      minLines: 3,
                      maxLines: 6,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Optional instruction for the assistant',
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    'Preferences',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Temperature ${_temperature.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Slider(
                    value: _temperature,
                    min: 0,
                    max: 2,
                    divisions: 20,
                    label: _temperature.toStringAsFixed(2),
                    onChanged: (double value) {
                      setState(() {
                        _temperature = value;
                      });
                    },
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Stream responses'),
                    subtitle: const Text(
                      'Use token streaming when the provider supports it.',
                    ),
                    value: _streamResponses,
                    onChanged: (bool value) {
                      setState(() {
                        _streamResponses = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ThemeMode>(
                    initialValue: _themeMode,
                    decoration: const InputDecoration(labelText: 'Theme mode'),
                    items: const <DropdownMenuItem<ThemeMode>>[
                      DropdownMenuItem<ThemeMode>(
                        value: ThemeMode.dark,
                        child: Text('Dark'),
                      ),
                      DropdownMenuItem<ThemeMode>(
                        value: ThemeMode.light,
                        child: Text('Light'),
                      ),
                      DropdownMenuItem<ThemeMode>(
                        value: ThemeMode.system,
                        child: Text('System'),
                      ),
                    ],
                    onChanged: (ThemeMode? value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _themeMode = value;
                      });
                    },
                  ),
                  if (ttsService.availableVoices.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: ttsService.availableVoices.any(
                        (Map<String, String> v) =>
                            v['name'] == ttsService.selectedVoiceName,
                      )
                          ? ttsService.selectedVoiceName
                          : null,
                      decoration:
                          const InputDecoration(labelText: 'TTS voice'),
                      items: ttsService.availableVoices
                          .map(
                            (Map<String, String> voice) =>
                                DropdownMenuItem<String>(
                              value: voice['name'],
                              child: Text(
                                '${voice['name']} (${voice['locale']})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (String? value) {
                        if (value == null) return;
                        final Map<String, String> voice =
                            ttsService.availableVoices.firstWhere(
                          (Map<String, String> v) => v['name'] == value,
                        );
                        ttsService.setVoice(
                          value,
                          voice['locale'] ?? '',
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 24),
                  const SizedBox(height: 12),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      'Web Search APIs (optional)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    children: <Widget>[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _tavilyApiKeyController,
                        obscureText: _obscureTavilyApiKey,
                        decoration: InputDecoration(
                          labelText: 'Tavily API key',
                          hintText: 'Free at tavily.com',
                          helperText:
                              'Best results + page content in one call',
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _obscureTavilyApiKey = !_obscureTavilyApiKey;
                              });
                            },
                            tooltip: _obscureTavilyApiKey
                                ? 'Show Tavily API key'
                                : 'Hide Tavily API key',
                            icon: Icon(
                              _obscureTavilyApiKey
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _exaApiKeyController,
                        obscureText: _obscureExaApiKey,
                        decoration: InputDecoration(
                          labelText: 'Exa API key',
                          hintText: 'Free at dashboard.exa.ai',
                          helperText:
                              'Neural search + LLM-ready highlights, replaces DuckDuckGo scraping',
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _obscureExaApiKey = !_obscureExaApiKey;
                              });
                            },
                            tooltip: _obscureExaApiKey
                                ? 'Show Exa API key'
                                : 'Hide Exa API key',
                            icon: Icon(
                              _obscureExaApiKey
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _braveSearchApiKeyController,
                        obscureText: _obscureBraveSearchApiKey,
                        decoration: InputDecoration(
                          labelText: 'Brave Search API key',
                          hintText: 'Free at api.search.brave.com',
                          helperText:
                              'Reliable JSON search, replaces DuckDuckGo scraping',
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _obscureBraveSearchApiKey =
                                    !_obscureBraveSearchApiKey;
                              });
                            },
                            tooltip: _obscureBraveSearchApiKey
                                ? 'Show Brave Search API key'
                                : 'Hide Brave Search API key',
                            icon: Icon(
                              _obscureBraveSearchApiKey
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _jinaApiKeyController,
                        obscureText: _obscureJinaApiKey,
                        decoration: InputDecoration(
                          labelText: 'Jina API key',
                          hintText: 'Free at jina.ai',
                          helperText:
                              'Higher rate limits for page content extraction',
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _obscureJinaApiKey = !_obscureJinaApiKey;
                              });
                            },
                            tooltip: _obscureJinaApiKey
                                ? 'Show Jina API key'
                                : 'Hide Jina API key',
                            icon: Icon(
                              _obscureJinaApiKey
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _firecrawlApiKeyController,
                        obscureText: _obscureFirecrawlApiKey,
                        decoration: InputDecoration(
                          labelText: 'Firecrawl API key',
                          hintText: 'Free at firecrawl.dev',
                          helperText:
                              'JS-rendered pages and anti-bot bypass',
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _obscureFirecrawlApiKey =
                                    !_obscureFirecrawlApiKey;
                              });
                            },
                            tooltip: _obscureFirecrawlApiKey
                                ? 'Show Firecrawl API key'
                                : 'Hide Firecrawl API key',
                            icon: Icon(
                              _obscureFirecrawlApiKey
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'Deep research rounds',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          Text(
                            _deepResearchMaxRounds == 0
                                ? 'Off'
                                : '$_deepResearchMaxRounds round${_deepResearchMaxRounds == 1 ? '' : 's'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      Slider(
                        value: _deepResearchMaxRounds.toDouble(),
                        min: 0,
                        max: 5,
                        divisions: 5,
                        label: _deepResearchMaxRounds == 0
                            ? 'Off'
                            : '$_deepResearchMaxRounds',
                        onChanged: (double value) {
                          setState(() {
                            _deepResearchMaxRounds = value.round();
                          });
                        },
                      ),
                      Text(
                        _deepResearchMaxRounds == 0
                            ? 'Single-pass search (fastest)'
                            : 'Follows up with $_deepResearchMaxRounds additional search${_deepResearchMaxRounds == 1 ? '' : 'es'} if needed',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: context.openChatPalette.mutedText,
                                ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                  if (_saveError != null) ...<Widget>[
                    Text(
                      _saveError!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save settings'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final ProviderConfig config = _draftConfig();
    final String? validationMessage = config.chatValidationMessage;
    if (validationMessage != null) {
      setState(() {
        _saveError = validationMessage;
      });
      return;
    }

    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      await widget.onSave(config, _themeMode);
      await widget.onSaveWebSearch(
        _jinaApiKeyController.text.trim(),
        _tavilyApiKeyController.text.trim(),
        _firecrawlApiKeyController.text.trim(),
        _braveSearchApiKeyController.text.trim(),
        _exaApiKeyController.text.trim(),
        _deepResearchMaxRounds,
      );
      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _saveError = _friendlyErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _applyPreset(String presetId) {
    final ProviderPreset preset = providerPresetById(presetId);
    setState(() {
      _selectedPresetId = presetId;
      _labelController.text = preset.defaultLabel;
      _baseUrlController.text = preset.defaultBaseUrl;
      _modelController.clear();
      _modelFetchSuccess = null;
      _modelFetchError = null;
      _saveError = null;
    });
    context.read<SettingsController>().clearAvailableModels();
  }

  ProviderConfig _draftConfig() {
    final ProviderPreset preset = providerPresetById(_selectedPresetId);
    return ProviderConfig(
      presetId: _selectedPresetId,
      label: _labelController.text.trim().isEmpty
          ? preset.defaultLabel
          : _labelController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim(),
      systemPrompt: _systemPromptController.text.trim(),
      temperature: _temperature,
      streamResponses: _streamResponses,
    );
  }

  Future<void> _fetchModels() async {
    setState(() {
      _fetchingModels = true;
      _modelFetchSuccess = null;
      _modelFetchError = null;
      _saveError = null;
    });

    try {
      final List<String> models =
          await context.read<SettingsController>().fetchModels(_draftConfig());
      if (!mounted) {
        return;
      }

      setState(() {
        final bool autoSelected =
            _modelController.text.trim().isEmpty && models.isNotEmpty;
        if (autoSelected) {
          _modelController.text = models.first;
        }
        if (models.isEmpty) {
          _modelFetchSuccess =
              'Connection successful, but this provider did not return any models. Enter one manually to continue.';
        } else if (autoSelected) {
          _modelFetchSuccess = models.length == 1
              ? 'Connection successful. Found 1 model and selected it for you.'
              : 'Connection successful. Found ${models.length} models and selected the first one.';
        } else {
          _modelFetchSuccess = models.length == 1
              ? 'Connection successful. Found 1 model.'
              : 'Connection successful. Found ${models.length} models.';
        }
        _saveError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _modelFetchSuccess = null;
        _modelFetchError = _friendlyErrorMessage(
          error,
          includeWebProxyHint: true,
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _fetchingModels = false;
        });
      }
    }
  }

  void _handleDraftChanged() {
    if (!mounted) {
      return;
    }

    setState(() {
      _modelFetchSuccess = null;
      _modelFetchError = null;
      _saveError = null;
    });
  }

  void _handleConnectionChanged() {
    if (!mounted) {
      return;
    }

    setState(() {
      _modelFetchSuccess = null;
      _modelFetchError = null;
      _saveError = null;
    });
    context.read<SettingsController>().clearAvailableModels();
  }

  String _friendlyErrorMessage(
    Object error, {
    bool includeWebProxyHint = false,
  }) {
    String message = error
        .toString()
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .replaceFirst(RegExp(r'^Bad state:\s*'), '')
        .trim();
    if (message.isEmpty) {
      message = 'Something went wrong.';
    }

    if (includeWebProxyHint && kIsWeb) {
      final String lower = message.toLowerCase();
      if (lower.contains('xmlhttprequest') ||
          lower.contains('clientexception') ||
          lower.contains('proxy connection failed') ||
          lower.contains('connection refused') ||
          lower.contains('failed host lookup')) {
        return '$message Make sure the local web proxy is running and the provider host is allowed.';
      }
    }

    return message;
  }
}
