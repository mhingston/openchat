import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openchat/src/models/attachment.dart';
import 'package:openchat/src/models/chat_message.dart';
import 'package:openchat/src/models/chat_thread.dart';
import 'package:openchat/src/services/chat_export_service.dart';

void main() {
  group('ChatExportService', () {
    test('exports threads as indented JSON', () {
      final ChatExportService service = ChatExportService();
      final List<ChatThread> threads = <ChatThread>[_sampleThread()];

      final String content = service.exportThreadsAsJson(threads);
      final Object? decoded = jsonDecode(content);

      expect(decoded, isA<List<dynamic>>());
      expect((decoded! as List<dynamic>).single['title'], 'Sprint planning');
    });

    test('exports threads as markdown transcript', () {
      final ChatExportService service = ChatExportService();

      final String content = service.exportThreadsAsMarkdown(
        <ChatThread>[_sampleThread()],
      );

      expect(content, contains('# OpenChat conversation export'));
      expect(content, contains('## Sprint planning'));
      expect(content, contains('### USER'));
      expect(content, contains('### ASSISTANT'));
      expect(content, contains('diagram.png'));
    });

    test('imports current-format JSON threads', () {
      final ChatExportService service = ChatExportService();
      final String content = service.exportThreadsAsJson(<ChatThread>[
        _sampleThread(),
      ]);

      final ImportResult result = service.importThreadsFromJson(content);

      expect(result.isSuccess, isTrue);
      expect(result.threads, hasLength(1));
      expect(result.threads!.single.messages, hasLength(2));
    });

    test('imports legacy payloads that use errorText and data', () {
      final ChatExportService service = ChatExportService();
      const String content = '''
[
  {
    "id": "thread-legacy",
    "title": "Legacy import",
    "createdAt": "2026-03-16T12:00:00.000",
    "updatedAt": "2026-03-16T12:00:00.000",
    "messages": [
      {
        "id": "message-1",
        "role": "assistant",
        "text": "",
        "createdAt": "2026-03-16T12:00:00.000",
        "attachments": [
          {
            "id": "attachment-1",
            "name": "legacy.txt",
            "data": "aGVsbG8=",
            "mimeType": "text/plain",
            "kind": "file",
            "sizeBytes": 5
          }
        ],
        "isStreaming": false,
        "errorText": "Legacy provider error"
      }
    ]
  }
]
''';

      final ImportResult result = service.importThreadsFromJson(content);

      expect(result.isSuccess, isTrue);
      expect(result.threads, hasLength(1));
      final ChatMessage message = result.threads!.single.messages.single;
      expect(message.text, 'Legacy provider error');
      expect(message.isError, isTrue);
      expect(message.attachments.single.base64Data, 'aGVsbG8=');
    });

    test('uses injected save and pick operations', () async {
      late String savedFileName;
      late Uint8List savedBytes;
      final ChatExportService service = ChatExportService(
        saveFile: ({
          required String fileName,
          required Uint8List bytes,
          required List<String> allowedExtensions,
        }) async {
          savedFileName = fileName;
          savedBytes = bytes;
          return '/tmp/$fileName';
        },
        pickImportBytes: () async => Uint8List.fromList(
          utf8.encode(serviceJsonFixture),
        ),
      );

      final String? exportLocation = await service.exportThread(
        thread: _sampleThread(),
        format: ExportFormat.json,
      );
      final ImportResult importResult = await service.importThreads();

      expect(exportLocation, contains('.json'));
      expect(savedFileName, contains('sprint-planning'));
      expect(utf8.decode(savedBytes), contains('Sprint planning'));
      expect(importResult.isSuccess, isTrue);
      expect(importResult.threads, hasLength(1));
    });
  });
}

const String serviceJsonFixture = '''
[
  {
    "id": "thread-1",
    "title": "Imported chat",
    "createdAt": "2026-03-16T12:00:00.000",
    "updatedAt": "2026-03-16T12:05:00.000",
    "messages": []
  }
]
''';

ChatThread _sampleThread() {
  final DateTime timestamp = DateTime(2026, 3, 16, 12, 0);
  return ChatThread(
    id: 'thread-1',
    title: 'Sprint planning',
    messages: <ChatMessage>[
      ChatMessage(
        id: 'message-1',
        role: ChatRole.user,
        text: 'Summarize the sprint goals.',
        createdAt: timestamp,
        attachments: const <ChatAttachment>[],
        isStreaming: false,
        isError: false,
      ),
      ChatMessage(
        id: 'message-2',
        role: ChatRole.assistant,
        text: 'Here is the update.',
        createdAt: timestamp,
        attachments: <ChatAttachment>[
          ChatAttachment(
            id: 'attachment-1',
            name: 'diagram.png',
            kind: AttachmentKind.image,
            mimeType: 'image/png',
            sizeBytes: 1200,
            previewText: 'Architecture diagram',
            createdAt: timestamp,
            base64Data: 'aGVsbG8=',
          ),
        ],
        isStreaming: false,
        isError: false,
      ),
    ],
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}
