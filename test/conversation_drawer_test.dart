import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openchat/src/models/chat_thread.dart';
import 'package:openchat/src/theme/app_theme.dart';
import 'package:openchat/src/widgets/conversation_drawer.dart';

void main() {
  testWidgets('drawer exposes export and import actions', (
    WidgetTester tester,
  ) async {
    int createThreadCount = 0;
    int exportAllCount = 0;
    int importCount = 0;
    int searchCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: ConversationDrawer(
          threads: <ChatThread>[
            ChatThread(
              id: 'thread-1',
              title: 'Sprint planning',
              messages: const [],
              createdAt: DateTime(2026, 3, 16, 12, 0),
              updatedAt: DateTime(2026, 3, 16, 12, 0),
            ),
          ],
          selectedThreadId: 'thread-1',
          onCreateThread: () async {
            createThreadCount += 1;
          },
          onOpenSearch: () async {
            searchCount += 1;
          },
          onSelectThread: (_) async {},
          onTogglePinnedThread: (_) async {},
          onRenameThread: (_) async {},
          onDuplicateThread: (_) async {},
          onDeleteThread: (_) async {},
          onExportAllThreads: () async {
            exportAllCount += 1;
          },
          onImportThreads: () async {
            importCount += 1;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('drawer-new-chat-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('drawer-search-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('drawer-export-all-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('drawer-import-button')));
    await tester.pump();

    expect(createThreadCount, 1);
    expect(searchCount, 1);
    expect(exportAllCount, 1);
    expect(importCount, 1);
    expect(find.byKey(const Key('drawer-export-current-button')), findsNothing);
    expect(find.byTooltip('New chat'), findsOneWidget);
  });

  testWidgets('drawer lets users pin a conversation', (
    WidgetTester tester,
  ) async {
    int pinCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: ConversationDrawer(
          threads: <ChatThread>[
            ChatThread(
              id: 'thread-1',
              title: 'Sprint planning',
              messages: const [],
              createdAt: DateTime(2026, 3, 16, 12, 0),
              updatedAt: DateTime(2026, 3, 16, 12, 0),
            ),
          ],
          selectedThreadId: 'thread-1',
          onCreateThread: () async {},
          onOpenSearch: () async {},
          onSelectThread: (_) async {},
          onTogglePinnedThread: (_) async {
            pinCount += 1;
          },
          onRenameThread: (_) async {},
          onDuplicateThread: (_) async {},
          onDeleteThread: (_) async {},
          onExportAllThreads: () async {},
          onImportThreads: () async {},
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin'));
    await tester.pumpAndSettle();

    expect(pinCount, 1);
  });
}
