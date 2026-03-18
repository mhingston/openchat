import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:openchat/src/models/attachment.dart';
import 'package:openchat/src/models/chat_message.dart';
import 'package:openchat/src/models/provider_config.dart';
import 'package:openchat/src/services/attachment_store.dart';
import 'package:openchat/src/services/openai_compatible_client.dart';

void main() {
  group('OpenAiCompatibleClient web proxying', () {
    test('routes OpenAI-compatible model fetches through the web proxy',
        () async {
      late Uri requestedUri;
      late Map<String, String> requestHeaders;
      final OpenAiCompatibleClient client = OpenAiCompatibleClient(
        isWebOverride: true,
        httpClient: MockClient((http.Request request) async {
          requestedUri = request.url;
          requestHeaders = Map<String, String>.from(request.headers);
          return http.Response(
            jsonEncode(<String, Object>{
              'data': <Map<String, String>>[
                <String, String>{'id': 'gpt-4o-mini'},
              ],
            }),
            200,
          );
        }),
      );

      final List<String> models = await client.listModels(
        config: const ProviderConfig(
          presetId: 'openai',
          label: 'OpenAI',
          baseUrl: 'https://api.openai.com/v1',
          apiKey: 'sk-openai',
          model: '',
          systemPrompt: '',
          temperature: 1,
          streamResponses: true,
        ),
      );

      expect(
        requestedUri.toString(),
        'http://127.0.0.1:8081/proxy?url=https%3A%2F%2Fapi.openai.com%2Fv1%2Fmodels',
      );
      expect(requestHeaders['Authorization'], 'Bearer sk-openai');
      expect(models, <String>['gpt-4o-mini']);
      client.dispose();
    });

    test('routes Ollama model fetches through the web proxy', () async {
      late Uri requestedUri;
      final OpenAiCompatibleClient client = OpenAiCompatibleClient(
        isWebOverride: true,
        httpClient: MockClient((http.Request request) async {
          requestedUri = request.url;
          return http.Response(
            jsonEncode(<String, Object>{
              'models': <Map<String, String>>[
                <String, String>{'name': 'gpt-oss:120b'},
              ],
            }),
            200,
          );
        }),
      );

      final List<String> models = await client.listModels(
        config: const ProviderConfig(
          presetId: 'ollama-cloud',
          label: 'Ollama Cloud',
          baseUrl: 'https://ollama.com',
          apiKey: 'sk-ollama',
          model: '',
          systemPrompt: '',
          temperature: 1,
          streamResponses: true,
        ),
      );

      expect(
        requestedUri.toString(),
        'http://127.0.0.1:8081/proxy?url=https%3A%2F%2Follama.com%2Fapi%2Ftags',
      );
      expect(models, <String>['gpt-oss:120b']);
      client.dispose();
    });

    test('keeps native requests direct', () async {
      late Uri requestedUri;
      final OpenAiCompatibleClient client = OpenAiCompatibleClient(
        isWebOverride: false,
        httpClient: MockClient((http.Request request) async {
          requestedUri = request.url;
          return http.Response(
            jsonEncode(<String, Object>{
              'data': <Map<String, String>>[
                <String, String>{'id': 'gpt-4o-mini'},
              ],
            }),
            200,
          );
        }),
      );

      await client.listModels(
        config: const ProviderConfig(
          presetId: 'openai',
          label: 'OpenAI',
          baseUrl: 'https://api.openai.com/v1',
          apiKey: 'sk-openai',
          model: '',
          systemPrompt: '',
          temperature: 1,
          streamResponses: true,
        ),
      );

      expect(requestedUri.toString(), 'https://api.openai.com/v1/models');
      client.dispose();
    });
  });

  group('OpenAiCompatibleClient attachments', () {
    const ProviderConfig openAiConfig = ProviderConfig(
      presetId: 'openai',
      label: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      apiKey: 'sk-openai',
      model: 'gpt-4.1-mini',
      systemPrompt: '',
      temperature: 1,
      streamResponses: false,
    );

    test('sends image attachments as multimodal OpenAI content', () async {
      late Map<String, dynamic> requestBody;
      final OpenAiCompatibleClient client = OpenAiCompatibleClient(
        attachmentStore: AttachmentStore.memory(),
        httpClient: MockClient((http.Request request) async {
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode(<String, Object>{
              'choices': <Map<String, Object>>[
                <String, Object>{
                  'message': <String, String>{'content': 'ok'},
                },
              ],
            }),
            200,
          );
        }),
      );

      await client.streamChatCompletion(
        config: openAiConfig,
        messages: <ChatMessage>[
          ChatMessage(
            id: 'm1',
            role: ChatRole.user,
            text: '',
            createdAt: DateTime.parse('2026-03-16T12:00:00.000Z'),
            attachments: <ChatAttachment>[
              ChatAttachment(
                id: 'a1',
                name: 'photo.png',
                kind: AttachmentKind.image,
                mimeType: 'image/png',
                sizeBytes: 3,
                previewText: 'Image • 3 B',
                createdAt: DateTime.parse('2026-03-16T12:00:00.000Z'),
                base64Data: base64Encode(<int>[1, 2, 3]),
              ),
            ],
            isStreaming: false,
            isError: false,
          ),
        ],
      ).toList();

      final List<dynamic> messages = requestBody['messages'] as List<dynamic>;
      final Map<String, dynamic> firstMessage =
          messages.first as Map<String, dynamic>;
      final List<dynamic> content = firstMessage['content'] as List<dynamic>;

      expect(firstMessage['role'], 'user');
      expect(content[0], <String, dynamic>{
        'type': 'text',
        'text': 'Attached image: photo.png',
      });
      expect((content[1] as Map<String, dynamic>)['type'], 'image_url');
      expect(
        ((content[1] as Map<String, dynamic>)['image_url']
            as Map<String, dynamic>)['url'],
        'data:image/png;base64,AQID',
      );
      client.dispose();
    });

    test('inlines readable text attachments into OpenAI content', () async {
      late Map<String, dynamic> requestBody;
      final OpenAiCompatibleClient client = OpenAiCompatibleClient(
        attachmentStore: AttachmentStore.memory(),
        httpClient: MockClient((http.Request request) async {
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode(<String, Object>{
              'choices': <Map<String, Object>>[
                <String, Object>{
                  'message': <String, String>{'content': 'ok'},
                },
              ],
            }),
            200,
          );
        }),
      );

      await client.streamChatCompletion(
        config: openAiConfig,
        messages: <ChatMessage>[
          ChatMessage(
            id: 'm1',
            role: ChatRole.user,
            text: 'Summarize this',
            createdAt: DateTime.parse('2026-03-16T12:00:00.000Z'),
            attachments: <ChatAttachment>[
              ChatAttachment(
                id: 'a1',
                name: 'notes.txt',
                kind: AttachmentKind.file,
                mimeType: 'text/plain',
                sizeBytes: 13,
                previewText: 'hello world',
                createdAt: DateTime.parse('2026-03-16T12:00:00.000Z'),
                base64Data: base64Encode(utf8.encode('hello world')),
              ),
            ],
            isStreaming: false,
            isError: false,
          ),
        ],
      ).toList();

      final List<dynamic> messages = requestBody['messages'] as List<dynamic>;
      final Map<String, dynamic> firstMessage =
          messages.first as Map<String, dynamic>;
      final List<dynamic> content = firstMessage['content'] as List<dynamic>;

      expect(content[0], <String, dynamic>{
        'type': 'text',
        'text': 'Summarize this',
      });
      expect(
        (content[1] as Map<String, dynamic>)['text'],
        'Attached document: notes.txt\nhello world',
      );
      client.dispose();
    });

    test('fails predictably for unsupported binary file attachments', () async {
      final OpenAiCompatibleClient client = OpenAiCompatibleClient(
        attachmentStore: AttachmentStore.memory(),
        httpClient: MockClient((http.Request request) async {
          return http.Response('{}', 200);
        }),
      );

      expect(
        () => client.streamChatCompletion(
          config: openAiConfig,
          messages: <ChatMessage>[
            ChatMessage(
              id: 'm1',
              role: ChatRole.user,
              text: '',
              createdAt: DateTime.parse('2026-03-16T12:00:00.000Z'),
              attachments: <ChatAttachment>[
                ChatAttachment(
                  id: 'a1',
                  name: 'report.pdf',
                  kind: AttachmentKind.file,
                  mimeType: 'application/pdf',
                  sizeBytes: 3,
                  previewText: 'PDF file',
                  createdAt: DateTime.parse('2026-03-16T12:00:00.000Z'),
                  base64Data: base64Encode(<int>[1, 2, 3]),
                ),
              ],
              isStreaming: false,
              isError: false,
            ),
          ],
        ).toList(),
        throwsA(
          predicate<Object>(
            (Object error) => error.toString().contains('report.pdf'),
          ),
        ),
      );
      client.dispose();
    });

    test('includes system messages passed in the request history', () async {
      late Map<String, dynamic> requestBody;
      final OpenAiCompatibleClient client = OpenAiCompatibleClient(
        httpClient: MockClient((http.Request request) async {
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode(<String, Object>{
              'choices': <Map<String, Object>>[
                <String, Object>{
                  'message': <String, String>{'content': 'ok'},
                },
              ],
            }),
            200,
          );
        }),
      );

      await client.streamChatCompletion(
        config: openAiConfig,
        messages: <ChatMessage>[
          ChatMessage(
            id: 'sys-1',
            role: ChatRole.system,
            text: 'Search context',
            createdAt: DateTime.parse('2026-03-16T12:00:00.000Z'),
            attachments: const <ChatAttachment>[],
            isStreaming: false,
            isError: false,
          ),
          ChatMessage(
            id: 'm1',
            role: ChatRole.user,
            text: 'Hello',
            createdAt: DateTime.parse('2026-03-16T12:00:00.000Z'),
            attachments: const <ChatAttachment>[],
            isStreaming: false,
            isError: false,
          ),
        ],
      ).drain<void>();

      final List<dynamic> messages = requestBody['messages'] as List<dynamic>;
      expect(messages.first['role'], 'system');
      expect(messages.first['content'], 'Search context');
      client.dispose();
    });
  });
}
