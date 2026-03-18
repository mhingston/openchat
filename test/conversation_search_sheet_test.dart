import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openchat/src/models/conversation_search_result.dart';
import 'package:openchat/src/theme/app_theme.dart';
import 'package:openchat/src/widgets/conversation_search_sheet.dart';

void main() {
  testWidgets('search sheet shows matches and selects a result',
      (WidgetTester tester) async {
    String? selectedThreadId;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Builder(
          builder: (BuildContext context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (BuildContext sheetContext) {
                        return SizedBox(
                          height: 500,
                          child: ConversationSearchSheet(
                            onSearch: (String query) {
                              if (query.trim().toLowerCase() != 'release') {
                                return const <ConversationSearchResult>[];
                              }
                              return <ConversationSearchResult>[
                                ConversationSearchResult(
                                  threadId: 'thread-1',
                                  threadTitle: 'Release planning',
                                  preview:
                                      'Need a release checklist for Friday.',
                                  matchLabel: 'Assistant message',
                                  updatedAt: DateTime(2026, 3, 18, 9),
                                  isPinned: true,
                                  messageId: 'message-1',
                                ),
                              ];
                            },
                            onResultSelected:
                                (ConversationSearchResult result) async {
                              selectedThreadId = result.threadId;
                            },
                          ),
                        );
                      },
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'release');
    await tester.pump();

    expect(find.text('Release planning'), findsOneWidget);
    expect(find.text('Assistant message'), findsOneWidget);

    await tester.tap(find.text('Release planning'));
    await tester.pumpAndSettle();

    expect(selectedThreadId, 'thread-1');
  });
}
