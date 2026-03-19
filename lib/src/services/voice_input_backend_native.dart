import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'voice_input_backend.dart';

class NativeVoiceInputBackend implements VoiceInputBackend {
  final stt.SpeechToText _speech = stt.SpeechToText();

  void Function(String)? _onResult;

  @override
  Future<bool> initialize({
    required void Function(String text) onResult,
    required void Function(String message) onError,
    required void Function(String status) onStatus,
  }) async {
    _onResult = onResult;
    return _speech.initialize(
      onError: (SpeechRecognitionError error) => onError(error.errorMsg),
      onStatus: onStatus,
    );
  }

  @override
  Future<void> startListening({
    required Duration listenFor,
    required Duration pauseFor,
  }) async {
    await _speech.listen(
      onResult: (SpeechRecognitionResult result) =>
          _onResult?.call(result.recognizedWords),
      listenFor: listenFor,
      pauseFor: pauseFor,
      cancelOnError: false,
      partialResults: true,
    );
  }

  @override
  Future<void> stopListening() async {
    await _speech.stop();
  }

  @override
  Future<void> cancelListening() async {
    await _speech.cancel();
  }

  @override
  void dispose() {
    _speech.cancel();
  }
}

VoiceInputBackend createVoiceInputBackend() => NativeVoiceInputBackend();
