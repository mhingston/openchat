import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openchat/src/models/attachment.dart';
import 'package:openchat/src/models/chat_message.dart';
import 'package:openchat/src/theme/app_theme.dart';
import 'package:openchat/src/widgets/chat_message_bubble.dart';

void main() {
  testWidgets(
    'assistant messages render markdown and preserve attachments',
    (WidgetTester tester) async {
      final List<MethodCall> clipboardCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          clipboardCalls.add(methodCall);
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Scaffold(
            body: ChatMessageBubble(
              message: ChatMessage(
                id: 'assistant-1',
                role: ChatRole.assistant,
                text: '''
Here is some `inlineCode`.

```dart
void main() {
  print("hello");
}
```
''',
                createdAt: DateTime(2026),
                attachments: <ChatAttachment>[
                  ChatAttachment(
                    id: 'attachment-1',
                    name: 'notes.txt',
                    kind: AttachmentKind.file,
                    mimeType: 'text/plain',
                    sizeBytes: 42,
                    previewText: 'Context file',
                    createdAt: DateTime(2026),
                  ),
                ],
                isStreaming: false,
                isError: false,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.text('notes.txt'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('markdown-code-copy-button')));
      await tester.pumpAndSettle();

      final MethodCall clipboardCall = clipboardCalls.lastWhere(
        (MethodCall methodCall) => methodCall.method == 'Clipboard.setData',
      );

      expect(find.text('Copied'), findsOneWidget);
      expect(clipboardCalls, isNotEmpty);
      expect(clipboardCall.method, 'Clipboard.setData');
      expect(
        (clipboardCall.arguments as Map<dynamic, dynamic>)['text'],
        contains('print("hello");'),
      );
      expect(find.text('Code copied.'), findsOneWidget);
    },
  );

  testWidgets('user messages stay plain selectable text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: ChatMessageBubble(
            message: ChatMessage(
              id: 'user-1',
              role: ChatRole.user,
              text: '**not markdown rendered**',
              createdAt: DateTime(2026),
              attachments: const <ChatAttachment>[],
              isStreaming: false,
              isError: false,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(MarkdownBody), findsNothing);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('**not markdown rendered**'), findsOneWidget);
  });

  testWidgets('user messages expose edit and fork actions', (
    WidgetTester tester,
  ) async {
    bool didEdit = false;
    bool didFork = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: ChatMessageBubble(
            message: ChatMessage(
              id: 'user-1',
              role: ChatRole.user,
              text: 'Edit me',
              createdAt: DateTime(2026),
              attachments: const <ChatAttachment>[],
              isStreaming: false,
              isError: false,
            ),
            onEdit: () => didEdit = true,
            onFork: () => didFork = true,
          ),
        ),
      ),
    );

    expect(find.text('You'), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Fork'), findsOneWidget);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(didEdit, isTrue);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fork'));
    await tester.pumpAndSettle();
    expect(didFork, isTrue);
  });
}
