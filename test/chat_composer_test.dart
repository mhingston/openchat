import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openchat/src/models/attachment.dart';
import 'package:openchat/src/theme/app_theme.dart';
import 'package:openchat/src/utils/keyboard_shortcuts.dart';
import 'package:openchat/src/widgets/chat_composer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    OpenChatKeyboardShortcuts.debugIsDesktopOrWebOverride = true;
    OpenChatKeyboardShortcuts.debugIsApplePlatformOverride = true;
  });

  tearDown(() {
    OpenChatKeyboardShortcuts.debugIsDesktopOrWebOverride = null;
    OpenChatKeyboardShortcuts.debugIsApplePlatformOverride = null;
  });

  Future<void> pumpComposer(
    WidgetTester tester, {
    required Future<bool> Function(
      String text,
      List<ChatAttachment> attachments,
      bool useWebSearch,
    ) onSend,
    String? draftText,
    int draftVersion = 0,
    String? editingLabel,
    VoidCallback? onCancelEdit,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: ChatComposer(
            enabled: true,
            busy: false,
            onSend: onSend,
            draftText: draftText,
            draftVersion: draftVersion,
            editingLabel: editingLabel,
            onCancelEdit: onCancelEdit,
          ),
        ),
      ),
    );
  }

  testWidgets('clear draft affordance removes text',
      (WidgetTester tester) async {
    await pumpComposer(
      tester,
      onSend: (String text, List<ChatAttachment> attachments,
              bool useWebSearch) async =>
          true,
    );

    await tester.enterText(find.byType(TextField), 'Keep this note');
    await tester.pump();

    expect(find.byKey(const Key('chat-composer-clear-draft')), findsOneWidget);

    await tester.tap(find.byKey(const Key('chat-composer-clear-draft')));
    await tester.pump();

    expect(find.text('Keep this note'), findsNothing);
  });

  testWidgets('desktop shortcut sends and clears a successful draft',
      (WidgetTester tester) async {
    int sendCount = 0;
    String? sentText;

    await pumpComposer(
      tester,
      onSend: (String text, List<ChatAttachment> attachments,
          bool useWebSearch) async {
        sendCount += 1;
        sentText = text;
        return true;
      },
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Send with shortcut');
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(sendCount, 1);
    expect(sentText, 'Send with shortcut');
    expect(find.text('Send with shortcut'), findsNothing);
  });

  testWidgets('draft stays in place when send is rejected',
      (WidgetTester tester) async {
    await pumpComposer(
      tester,
      onSend: (String text, List<ChatAttachment> attachments,
              bool useWebSearch) async =>
          false,
    );

    await tester.enterText(find.byType(TextField), 'Needs retry');
    await tester.pump();

    await tester.tap(find.byKey(const Key('chat-composer-send-button')));
    await tester.pump();

    expect(find.text('Needs retry'), findsOneWidget);
  });

  testWidgets('external draft version loads edit text and cancel clears edit',
      (WidgetTester tester) async {
    int cancelCount = 0;

    await pumpComposer(
      tester,
      draftText: 'Rework this prompt',
      draftVersion: 1,
      editingLabel: 'Editing message',
      onCancelEdit: () => cancelCount += 1,
      onSend: (String text, List<ChatAttachment> attachments,
              bool useWebSearch) async =>
          true,
    );
    await tester.pump();

    expect(find.text('Editing message'), findsOneWidget);
    expect(find.text('Rework this prompt'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(cancelCount, 1);
  });

  testWidgets('web search toggle passes enabled state to onSend',
      (WidgetTester tester) async {
    bool? capturedUseWebSearch;

    await pumpComposer(
      tester,
      onSend: (
        String text,
        List<ChatAttachment> attachments,
        bool useWebSearch,
      ) async {
        capturedUseWebSearch = useWebSearch;
        return true;
      },
    );

    await tester.tap(find.byKey(const Key('chat-composer-web-search-toggle')));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Search this');
    await tester.pump();
    await tester.tap(find.byKey(const Key('chat-composer-send-button')));
    await tester.pump();

    expect(capturedUseWebSearch, isTrue);
  });
}
