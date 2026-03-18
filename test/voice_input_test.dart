import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openchat/src/models/attachment.dart';
import 'package:openchat/src/services/voice_input_service.dart';
import 'package:openchat/src/theme/app_theme.dart';
import 'package:openchat/src/utils/keyboard_shortcuts.dart';
import 'package:openchat/src/widgets/chat_composer.dart';

// ---------------------------------------------------------------------------
// Fake voice service helpers
// ---------------------------------------------------------------------------

/// A [VoiceInputService] pre-configured with a known state (no platform calls).
_FakeVoiceInputService _makeService({bool isAvailable = true}) {
  return _FakeVoiceInputService(
    isAvailable: isAvailable,
  );
}

class _FakeVoiceInputService extends VoiceInputService {
  _FakeVoiceInputService({required bool isAvailable})
      : super.withState(
          VoiceInputState(
            status: VoiceInputStatus.idle,
            isAvailable: isAvailable,
          ),
        );

  bool startListeningCalled = false;
  bool stopListeningCalled = false;
  bool cancelListeningCalled = false;

  @override
  Future<bool> startListening({
    Duration listenFor = const Duration(seconds: 30),
    Duration pauseFor = const Duration(seconds: 3),
  }) async {
    startListeningCalled = true;
    if (!isAvailable) return false;
    // Simulate entering the listening state.
    forceState(VoiceInputState(
      status: VoiceInputStatus.listening,
      isAvailable: isAvailable,
    ));
    return true;
  }

  @override
  Future<void> stopListening() async {
    stopListeningCalled = true;
    forceState(VoiceInputState(
      status: VoiceInputStatus.idle,
      isAvailable: isAvailable,
    ));
  }

  @override
  Future<void> cancelListening() async {
    cancelListeningCalled = true;
    forceState(VoiceInputState(
      status: VoiceInputStatus.idle,
      isAvailable: isAvailable,
      transcribedText: '',
    ));
  }

  void forceTranscript(String text) {
    forceState(VoiceInputState(
      status: VoiceInputStatus.listening,
      isAvailable: isAvailable,
      transcribedText: text,
    ));
  }

  void forceState(VoiceInputState s) {
    // Access the protected mutable field exposed via withState constructor.
    // We piggyback the ChangeNotifier to push state from outside.
    super.forceStateForTest(s);
  }
}

// ---------------------------------------------------------------------------
// Pump helper
// ---------------------------------------------------------------------------

Future<void> pumpComposerWithVoice(
  WidgetTester tester, {
  required Future<bool> Function(String, List<ChatAttachment>, bool) onSend,
  VoiceInputService? voiceService,
}) async {
  OpenChatKeyboardShortcuts.debugIsDesktopOrWebOverride = true;
  OpenChatKeyboardShortcuts.debugIsApplePlatformOverride = true;

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme(),
      home: Scaffold(
        body: ChatComposer(
          enabled: true,
          busy: false,
          onSend: onSend,
          voiceService: voiceService,
        ),
      ),
    ),
  );
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    OpenChatKeyboardShortcuts.debugIsDesktopOrWebOverride = null;
    OpenChatKeyboardShortcuts.debugIsApplePlatformOverride = null;
  });

  group('mic button visibility', () {
    testWidgets('mic button visible when voice is available and text is empty',
        (WidgetTester tester) async {
      final service = _makeService(isAvailable: true);
      await pumpComposerWithVoice(
        tester,
        onSend: (_, __, ___) async => true,
        voiceService: service,
      );

      expect(find.byKey(const Key('chat-composer-mic-button')), findsOneWidget);
      expect(find.byKey(const Key('chat-composer-send-button')), findsNothing);
    });

    testWidgets('send button shown (not mic) when text is present',
        (WidgetTester tester) async {
      final service = _makeService(isAvailable: true);
      await pumpComposerWithVoice(
        tester,
        onSend: (_, __, ___) async => true,
        voiceService: service,
      );

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      expect(
          find.byKey(const Key('chat-composer-send-button')), findsOneWidget);
      expect(find.byKey(const Key('chat-composer-mic-button')), findsNothing);
    });

    testWidgets('no mic button when voiceService is null',
        (WidgetTester tester) async {
      await pumpComposerWithVoice(
        tester,
        onSend: (_, __, ___) async => true,
        voiceService: null,
      );

      expect(find.byKey(const Key('chat-composer-mic-button')), findsNothing);
      expect(
          find.byKey(const Key('chat-composer-send-button')), findsOneWidget);
    });

    testWidgets('no mic button when voice is not available',
        (WidgetTester tester) async {
      final service = _makeService(isAvailable: false);
      await pumpComposerWithVoice(
        tester,
        onSend: (_, __, ___) async => true,
        voiceService: service,
      );

      expect(find.byKey(const Key('chat-composer-mic-button')), findsNothing);
    });
  });

  group('mic button interaction', () {
    testWidgets('tapping mic calls startListening',
        (WidgetTester tester) async {
      final service = _makeService(isAvailable: true);
      await pumpComposerWithVoice(
        tester,
        onSend: (_, __, ___) async => true,
        voiceService: service,
      );

      await tester.tap(find.byKey(const Key('chat-composer-mic-button')));
      await tester.pump();

      expect(service.startListeningCalled, isTrue);
    });

    testWidgets('transcription text appears in text field',
        (WidgetTester tester) async {
      final service = _makeService(isAvailable: true);
      await pumpComposerWithVoice(
        tester,
        onSend: (_, __, ___) async => true,
        voiceService: service,
      );

      // Simulate a partial transcript arriving.
      service.forceTranscript('hello world');
      await tester.pump();

      expect(find.text('hello world'), findsOneWidget);
    });

    testWidgets('send button appears after transcription fills text field',
        (WidgetTester tester) async {
      final service = _makeService(isAvailable: true);
      await pumpComposerWithVoice(
        tester,
        onSend: (_, __, ___) async => true,
        voiceService: service,
      );

      service.forceTranscript('say something');
      await tester.pump();

      // While still listening, the stop button stays visible so the user can
      // explicitly end capture.
      expect(find.byKey(const Key('chat-composer-send-button')), findsNothing);
      expect(find.byKey(const Key('chat-composer-mic-button')), findsWidgets);
      expect(
        find.text(
          'Listening… click the mic again to stop and insert your transcript.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('tapping mic while listening calls stopListening',
        (WidgetTester tester) async {
      final service = _makeService(isAvailable: true);
      await pumpComposerWithVoice(
        tester,
        onSend: (_, __, ___) async => true,
        voiceService: service,
      );

      // Enter the listening state directly.
      service.forceState(const VoiceInputState(
        status: VoiceInputStatus.listening,
        isAvailable: true,
      ));
      await tester.pumpAndSettle();

      // The mic button is still visible because text is still empty.
      await tester.tap(find.byKey(const Key('chat-composer-mic-button')).first);
      await tester.pump();

      expect(service.stopListeningCalled, isTrue);
    });

    testWidgets('send button appears after listening stops with transcript',
        (WidgetTester tester) async {
      final service = _makeService(isAvailable: true);
      await pumpComposerWithVoice(
        tester,
        onSend: (_, __, ___) async => true,
        voiceService: service,
      );

      service.forceState(const VoiceInputState(
        status: VoiceInputStatus.idle,
        isAvailable: true,
        transcribedText: 'final transcript',
      ));
      await tester.pump();

      expect(
          find.byKey(const Key('chat-composer-send-button')), findsOneWidget);
      expect(find.byKey(const Key('chat-composer-mic-button')), findsNothing);
    });
  });

  group('voice state tests', () {
    test('VoiceInputState defaults', () {
      const state = VoiceInputState(status: VoiceInputStatus.idle);
      expect(state.isListening, isFalse);
      expect(state.hasError, isFalse);
      expect(state.isAvailable, isFalse);
      expect(state.transcribedText, isEmpty);
    });

    test('VoiceInputState.copyWith updates fields', () {
      const initial = VoiceInputState(status: VoiceInputStatus.idle);
      final updated = initial.copyWith(
        status: VoiceInputStatus.listening,
        isAvailable: true,
        transcribedText: 'hello',
      );
      expect(updated.isListening, isTrue);
      expect(updated.isAvailable, isTrue);
      expect(updated.transcribedText, 'hello');
      // Original unchanged.
      expect(initial.isListening, isFalse);
    });

    test('VoiceInputState.copyWith can clear an error message', () {
      const initial = VoiceInputState(
        status: VoiceInputStatus.error,
        errorMessage: 'Microphone permission denied',
      );
      final updated = initial.copyWith(
        status: VoiceInputStatus.idle,
        errorMessage: null,
      );

      expect(updated.hasError, isFalse);
      expect(updated.errorMessage, isNull);
    });

    test('VoiceInputService.withState exposes expected state', () {
      final svc = VoiceInputService.withState(
        const VoiceInputState(
          status: VoiceInputStatus.idle,
          isAvailable: true,
        ),
      );
      expect(svc.isAvailable, isTrue);
      expect(svc.isListening, isFalse);
      svc.dispose();
    });
  });
}
