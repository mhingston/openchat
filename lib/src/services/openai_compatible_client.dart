import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/attachment.dart';
import '../models/chat_message.dart';
import '../models/provider_config.dart';
import 'attachment_store.dart';

class ChatCompletionChunk {
  const ChatCompletionChunk({required this.delta, required this.isDone});

  const ChatCompletionChunk.done()
      : delta = '',
        isDone = true;

  final String delta;
  final bool isDone;
}

class OpenAiCompatibleClient {
  OpenAiCompatibleClient({
    http.Client? httpClient,
    bool? isWebOverride,
    String webProxyUrl = _defaultWebProxyUrl,
    AttachmentStore? attachmentStore,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _isWeb = isWebOverride ?? kIsWeb,
        _webProxyUrl = webProxyUrl,
        _attachmentStore = attachmentStore;

  http.Client _httpClient;
  final bool _ownsClient;
  final bool _isWeb;
  final String _webProxyUrl;
  final AttachmentStore? _attachmentStore;
  Future<AttachmentStore>? _attachmentStoreFuture;

  Stream<ChatCompletionChunk> streamChatCompletion({
    required ProviderConfig config,
    required List<ChatMessage> messages,
  }) async* {
    if (!config.isValidForChat) {
      throw StateError('Provider settings are incomplete.');
    }

    final String corsProxyUrl = _resolvedCorsProxyUrl();
    final bool useBufferedOllamaWebResponse = _isWeb && config.usesOllamaApi;
    final Uri uri = config.usesOllamaApi
        ? _ollamaChatUri(config, corsProxyUrl: corsProxyUrl)
        : _appendedUri(
            config.normalizedBaseUrl,
            <String>['chat', 'completions'],
            corsProxyUrl: corsProxyUrl,
          );
    final Map<String, dynamic> payload = await _buildPayload(
      config: config,
      messages: messages,
    );

    if (!config.streamResponses || useBufferedOllamaWebResponse) {
      final Map<String, dynamic> requestBody =
          Map<String, dynamic>.from(payload)..['stream'] = false;

      final http.Response response = await _httpClient.post(
        uri,
        headers: _headers(config),
        body: jsonEncode(requestBody),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Provider request failed (${response.statusCode}): ${response.body}',
        );
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid provider response.');
      }

      final String content = config.usesOllamaApi
          ? _extractOllamaMessageContent(decoded)
          : _extractMessageContent(decoded);
      if (content.isNotEmpty) {
        yield ChatCompletionChunk(delta: content, isDone: false);
      }
      yield const ChatCompletionChunk.done();
      return;
    }

    final Map<String, dynamic> requestBody = Map<String, dynamic>.from(payload)
      ..['stream'] = true;

    final http.Request request = http.Request('POST', uri)
      ..headers.addAll(_headers(config))
      ..body = jsonEncode(requestBody);

    final http.StreamedResponse response = await _httpClient.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final String body = await response.stream.bytesToString();
      throw Exception(
        'Provider request failed (${response.statusCode}): $body',
      );
    }

    if (config.usesOllamaApi) {
      await for (final String line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final String trimmed = line.trim();
        if (trimmed.isEmpty) {
          continue;
        }

        final Object? decoded = jsonDecode(trimmed);
        if (decoded is! Map<String, dynamic>) {
          continue;
        }

        final String delta = _extractOllamaMessageContent(decoded);
        if (delta.isNotEmpty) {
          yield ChatCompletionChunk(delta: delta, isDone: false);
        }

        if (decoded['done'] == true) {
          yield const ChatCompletionChunk.done();
          return;
        }
      }
    } else {
      await for (final String line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final String trimmed = line.trim();
        if (trimmed.isEmpty || !trimmed.startsWith('data:')) {
          continue;
        }

        final String rawData = trimmed.substring(5).trim();
        if (rawData == '[DONE]') {
          yield const ChatCompletionChunk.done();
          return;
        }

        final Object? decoded = jsonDecode(rawData);
        if (decoded is! Map<String, dynamic>) {
          continue;
        }

        final String delta = _extractDeltaContent(decoded);
        if (delta.isNotEmpty) {
          yield ChatCompletionChunk(delta: delta, isDone: false);
        }
      }
    }

    yield const ChatCompletionChunk.done();
  }

  Future<List<String>> listModels({required ProviderConfig config}) async {
    final String baseUrl = config.normalizedBaseUrl;
    final String corsProxyUrl = _resolvedCorsProxyUrl();
    if (baseUrl.isEmpty) {
      throw StateError('Add a base URL before fetching models.');
    }
    if (config.requiresApiKey && config.apiKey.trim().isEmpty) {
      throw StateError('Add an API key before fetching models.');
    }

    Exception? primaryError;
    if (!config.usesOllamaApi) {
      try {
        final Uri modelsUri = _appendedUri(
          baseUrl,
          <String>['models'],
          corsProxyUrl: corsProxyUrl,
        );
        final http.Response response = await _httpClient.get(
          modelsUri,
          headers: _headers(config),
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final Object? decoded = jsonDecode(response.body);
          final List<String> models = _extractModelIds(decoded);
          if (models.isNotEmpty) {
            return models;
          }
        } else {
          primaryError = Exception(
            'Provider model lookup failed (${response.statusCode}): ${response.body}',
          );
        }
      } catch (error) {
        primaryError = Exception(error.toString());
      }
    }

    try {
      final Uri ollamaUri = _ollamaTagsUri(
        baseUrl,
        corsProxyUrl: corsProxyUrl,
      );
      final http.Response response = await _httpClient.get(
        ollamaUri,
        headers: _headers(config),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Provider model lookup failed (${response.statusCode}): ${response.body}',
        );
      }

      final Object? decoded = jsonDecode(response.body);
      final List<String> models = _extractOllamaModelIds(decoded);
      if (models.isNotEmpty) {
        return models;
      }
    } catch (_) {
      if (primaryError != null) {
        throw primaryError;
      }
    }

    throw primaryError ?? Exception('No models were returned by the provider.');
  }

  /// Generates a short conversation title using a single non-streaming request.
  /// Returns null on any failure so the caller can ignore it gracefully.
  Future<String?> generateTitle({
    required ProviderConfig config,
    required String userMessage,
    required String assistantMessage,
  }) async {
    if (!config.isValidForChat) {
      return null;
    }
    try {
      final String corsProxyUrl = _resolvedCorsProxyUrl();
      final Uri uri = config.usesOllamaApi
          ? _ollamaChatUri(config, corsProxyUrl: corsProxyUrl)
          : _appendedUri(
              config.normalizedBaseUrl,
              <String>['chat', 'completions'],
              corsProxyUrl: corsProxyUrl,
            );

      final String userSnippet = userMessage.length > 300
          ? '${userMessage.substring(0, 300)}…'
          : userMessage;
      final String assistantSnippet = assistantMessage.length > 300
          ? '${assistantMessage.substring(0, 300)}…'
          : assistantMessage;
      const String prompt =
          'In 6 words or fewer, write a title for this conversation. '
          'Output only the title text — no quotes, no trailing punctuation.';

      final Map<String, dynamic> payload = <String, dynamic>{
        'model': config.model.trim(),
        'temperature': 0.3,
        'stream': false,
        'max_tokens': 20,
        'messages': <Map<String, dynamic>>[
          <String, dynamic>{
            'role': 'user',
            'content':
                '$prompt\n\nUser: $userSnippet\nAssistant: $assistantSnippet',
          },
        ],
      };

      final http.Response response = await _httpClient
          .post(
            uri,
            headers: _headers(config),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final String content = config.usesOllamaApi
          ? _extractOllamaMessageContent(decoded)
          : _extractMessageContent(decoded);

      final String title = content
          .trim()
          .replaceAll(RegExp(r'''^["']+|["']+$'''), '')
          .trim();
      return title.isEmpty ? null : title;
    } catch (_) {
      return null;
    }
  }

  /// Makes a single non-streaming chat completion and returns the raw response
  /// text, or `null` on any error. Used for lightweight planning calls.
  Future<String?> completeChat({
    required ProviderConfig config,
    required List<Map<String, dynamic>> messages,
    int maxTokens = 256,
    double temperature = 0.1,
  }) async {
    if (!config.isValidForChat) {
      return null;
    }
    try {
      final String corsProxyUrl = _resolvedCorsProxyUrl();
      final Uri uri = config.usesOllamaApi
          ? _ollamaChatUri(config, corsProxyUrl: corsProxyUrl)
          : _appendedUri(
              config.normalizedBaseUrl,
              <String>['chat', 'completions'],
              corsProxyUrl: corsProxyUrl,
            );

      final Map<String, dynamic> payload = <String, dynamic>{
        'model': config.model.trim(),
        'temperature': temperature,
        'stream': false,
        'max_tokens': maxTokens,
        'messages': messages,
      };

      final http.Response response = await _httpClient
          .post(
            uri,
            headers: _headers(config),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final String content = config.usesOllamaApi
          ? _extractOllamaMessageContent(decoded)
          : _extractMessageContent(decoded);

      return content.trim().isEmpty ? null : content.trim();
    } catch (_) {
      return null;
    }
  }

  /// Closes the current HTTP client and creates a fresh one. Call this when
  /// the app returns to the foreground so stale OS-level connections are
  /// discarded and DNS resolution starts clean.
  void resetHttpClient() {
    if (_ownsClient) {
      _httpClient.close();
      _httpClient = http.Client();
    }
  }

  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }

  String _resolvedCorsProxyUrl() {
    if (_isWeb) {
      return _webProxyUrl;
    }

    return '';
  }

  Map<String, String> _headers(ProviderConfig config) {
    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
    };
    final String apiKey = config.apiKey.trim();
    if (apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    return headers;
  }

  Uri _appendedUri(
    String baseUrl,
    List<String> pathSegments, {
    String corsProxyUrl = '',
  }) {
    final Uri baseUri = Uri.parse(baseUrl);
    final List<String> existingSegments = baseUri.pathSegments
        .where((String segment) => segment.isNotEmpty)
        .toList();
    final Uri targetUri = baseUri.replace(
      pathSegments: <String>[...existingSegments, ...pathSegments],
      queryParameters: null,
    );
    return _maybeProxyUri(targetUri, corsProxyUrl);
  }

  Uri _ollamaChatUri(ProviderConfig config, {required String corsProxyUrl}) {
    return _appendedUri(
      config.normalizedBaseUrl,
      <String>['api', 'chat'],
      corsProxyUrl: corsProxyUrl,
    );
  }

  Future<Map<String, dynamic>> _buildPayload({
    required ProviderConfig config,
    required List<ChatMessage> messages,
  }) async {
    final List<Map<String, dynamic>> payloadMessages = <Map<String, dynamic>>[];

    if (config.systemPrompt.trim().isNotEmpty) {
      payloadMessages.add(<String, dynamic>{
        'role': ChatRole.system.name,
        'content': config.systemPrompt.trim(),
      });
    }

    for (final ChatMessage message in messages) {
      if (message.role == ChatRole.system) {
        payloadMessages.add(<String, dynamic>{
          'role': ChatRole.system.name,
          'content': message.text.trim(),
        });
        continue;
      }
      payloadMessages.add(
        config.usesOllamaApi
            ? await _composeOllamaMessage(message)
            : await _composeOpenAiMessage(message),
      );
    }

    return <String, dynamic>{
      'model': config.model.trim(),
      'temperature': config.temperature,
      'stream': config.streamResponses,
      'messages': payloadMessages,
    };
  }

  Future<Map<String, dynamic>> _composeOpenAiMessage(
      ChatMessage message) async {
    if (message.attachments.isEmpty) {
      return <String, dynamic>{
        'role': message.role.name,
        'content': message.text.trim(),
      };
    }

    final AttachmentStore store = await _resolveAttachmentStore();
    final List<Map<String, dynamic>> content = <Map<String, dynamic>>[];
    final String trimmedText = message.text.trim();
    if (trimmedText.isNotEmpty) {
      content.add(<String, dynamic>{'type': 'text', 'text': trimmedText});
    }

    for (final ChatAttachment attachment in message.attachments) {
      if (attachment.kind == AttachmentKind.image) {
        content.add(<String, dynamic>{
          'type': 'text',
          'text': 'Attached image: ${attachment.name}',
        });
        content.add(<String, dynamic>{
          'type': 'image_url',
          'image_url': <String, dynamic>{
            'url': await store.toImageDataUrl(attachment),
          },
        });
        continue;
      }

      if (attachment.kind == AttachmentKind.note) {
        content.add(<String, dynamic>{
          'type': 'text',
          'text': _composeNoteAttachmentText(attachment),
        });
        continue;
      }

      final String documentText = await store.readTextFile(attachment);
      content.add(<String, dynamic>{
        'type': 'text',
        'text': _composeDocumentAttachmentText(
          attachment: attachment,
          documentText: documentText,
        ),
      });
    }

    if (content.isEmpty) {
      content.add(const <String, dynamic>{'type': 'text', 'text': ''});
    }

    return <String, dynamic>{
      'role': message.role.name,
      'content': content,
    };
  }

  Future<Map<String, dynamic>> _composeOllamaMessage(
      ChatMessage message) async {
    final StringBuffer buffer = StringBuffer(message.text.trim());
    final List<String> images = <String>[];

    if (message.attachments.isNotEmpty) {
      final AttachmentStore store = await _resolveAttachmentStore();
      for (final ChatAttachment attachment in message.attachments) {
        if (buffer.isNotEmpty) {
          buffer.writeln();
          buffer.writeln();
        }

        if (attachment.kind == AttachmentKind.image) {
          buffer.write('Attached image: ${attachment.name}');
          images.add(await store.readBase64Data(attachment));
          continue;
        }

        if (attachment.kind == AttachmentKind.note) {
          buffer.write(_composeNoteAttachmentText(attachment));
          continue;
        }

        final String documentText = await store.readTextFile(attachment);
        buffer.write(
          _composeDocumentAttachmentText(
            attachment: attachment,
            documentText: documentText,
          ),
        );
      }
    }

    return <String, dynamic>{
      'role': message.role.name,
      'content': buffer.toString().trim(),
      if (images.isNotEmpty) 'images': images,
    };
  }

  Future<AttachmentStore> _resolveAttachmentStore() {
    final AttachmentStore? injectedStore = _attachmentStore;
    if (injectedStore != null) {
      return Future<AttachmentStore>.value(injectedStore);
    }

    return _attachmentStoreFuture ??= AttachmentStore.create();
  }

  String _composeNoteAttachmentText(ChatAttachment attachment) {
    final String preview = attachment.previewText.trim();
    if (preview.isEmpty) {
      return 'Attachment note: ${attachment.name}';
    }
    return 'Attachment note: ${attachment.name}\n$preview';
  }

  String _composeDocumentAttachmentText({
    required ChatAttachment attachment,
    required String documentText,
  }) {
    final String trimmed = documentText.trim();
    if (trimmed.isEmpty) {
      return 'Attached document: ${attachment.name}\n(Empty text attachment)';
    }

    final String safeText = trimmed.length > _maxAttachmentTextCharacters
        ? '${trimmed.substring(0, _maxAttachmentTextCharacters)}\n\n[Attachment truncated after $_maxAttachmentTextCharacters characters.]'
        : trimmed;
    return 'Attached document: ${attachment.name}\n$safeText';
  }

  String _extractDeltaContent(Map<String, dynamic> json) {
    final List<dynamic> choices =
        json['choices'] as List<dynamic>? ?? <dynamic>[];
    if (choices.isEmpty) {
      return '';
    }

    final Object? firstChoiceRaw = choices.first;
    if (firstChoiceRaw is! Map<String, dynamic>) {
      return '';
    }

    final Object? delta = firstChoiceRaw['delta'];
    if (delta is Map<String, dynamic>) {
      return _extractContentField(delta['content']);
    }

    final Object? message = firstChoiceRaw['message'];
    if (message is Map<String, dynamic>) {
      return _extractContentField(message['content']);
    }

    return '';
  }

  String _extractMessageContent(Map<String, dynamic> json) {
    final List<dynamic> choices =
        json['choices'] as List<dynamic>? ?? <dynamic>[];
    if (choices.isEmpty) {
      return '';
    }

    final Object? firstChoiceRaw = choices.first;
    if (firstChoiceRaw is! Map<String, dynamic>) {
      return '';
    }

    final Object? message = firstChoiceRaw['message'];
    if (message is Map<String, dynamic>) {
      return _extractContentField(message['content']);
    }

    final Object? text = firstChoiceRaw['text'];
    if (text is String) {
      return text.trim();
    }

    return '';
  }

  String _extractOllamaMessageContent(Map<String, dynamic> json) {
    final Object? message = json['message'];
    if (message is Map<String, dynamic>) {
      final Object? content = message['content'];
      if (content is String) {
        return content;
      }
    }

    final Object? response = json['response'];
    if (response is String) {
      return response;
    }

    return '';
  }

  String _extractContentField(Object? rawContent) {
    if (rawContent is String) {
      return rawContent;
    }

    if (rawContent is List<dynamic>) {
      final StringBuffer buffer = StringBuffer();
      for (final dynamic item in rawContent) {
        if (item is Map<String, dynamic>) {
          final Object? text = item['text'];
          if (text is String) {
            if (buffer.isNotEmpty) {
              buffer.writeln();
            }
            buffer.write(text);
          }
        }
      }
      return buffer.toString();
    }

    return '';
  }

  List<String> _extractModelIds(Object? decoded) {
    if (decoded is! Map<String, dynamic>) {
      return const <String>[];
    }

    final Object? rawData = decoded['data'];
    if (rawData is! List<dynamic>) {
      return const <String>[];
    }

    final List<String> models = rawData
        .map((dynamic item) {
          if (item is Map<String, dynamic>) {
            final Object? id = item['id'];
            if (id is String && id.trim().isNotEmpty) {
              return id.trim();
            }
          }
          return '';
        })
        .where((String model) => model.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return models;
  }

  List<String> _extractOllamaModelIds(Object? decoded) {
    if (decoded is! Map<String, dynamic>) {
      return const <String>[];
    }

    final Object? rawModels = decoded['models'];
    if (rawModels is! List<dynamic>) {
      return const <String>[];
    }

    final List<String> models = rawModels
        .map((dynamic item) {
          if (item is Map<String, dynamic>) {
            final Object? name = item['name'];
            if (name is String && name.trim().isNotEmpty) {
              return name.trim();
            }
          }
          return '';
        })
        .where((String model) => model.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return models;
  }

  Uri _ollamaTagsUri(String normalizedBaseUrl, {String corsProxyUrl = ''}) {
    final Uri uri = Uri.parse(normalizedBaseUrl);
    final List<String> pathSegments =
        uri.pathSegments.where((String segment) => segment.isNotEmpty).toList();
    if (pathSegments.isNotEmpty && pathSegments.last == 'v1') {
      pathSegments.removeLast();
    }

    final Uri targetUri = uri.replace(
      pathSegments: <String>[...pathSegments, 'api', 'tags'],
      queryParameters: null,
    );
    return _maybeProxyUri(targetUri, corsProxyUrl);
  }

  Uri _maybeProxyUri(Uri targetUri, String corsProxyUrl) {
    final String trimmedProxy = corsProxyUrl.trim();
    if (trimmedProxy.isEmpty) {
      return targetUri;
    }

    final Uri proxyUri = Uri.parse(trimmedProxy);
    final bool isBareProxyOrigin =
        proxyUri.path.isEmpty || proxyUri.path == '/';
    final bool isProxyEndpoint = proxyUri.path == '/proxy';
    final String proxyPath = isBareProxyOrigin
        ? '/proxy'
        : (isProxyEndpoint ? proxyUri.path : proxyUri.path);

    return proxyUri.replace(
      path: proxyPath,
      queryParameters: <String, String>{
        ...proxyUri.queryParameters,
        'url': targetUri.toString(),
      },
    );
  }
}

const String _defaultWebProxyUrl = 'http://127.0.0.1:8081';
const int _maxAttachmentTextCharacters = 12000;
