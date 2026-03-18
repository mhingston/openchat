import 'voice_input_backend.dart';

class UnsupportedVoiceInputBackend implements VoiceInputBackend {
  @override
  Future<bool> initialize({
    required void Function(String text) onResult,
    required void Function(String message) onError,
    required void Function(String status) onStatus,
  }) async {
    return false;
  }

  @override
  Future<void> startListening({
    required Duration listenFor,
    required Duration pauseFor,
  }) async {
    throw StateError('Voice input is unavailable on this platform.');
  }

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> cancelListening() async {}

  @override
  void dispose() {}
}

VoiceInputBackend createVoiceInputBackend() => UnsupportedVoiceInputBackend();
