abstract class VoiceInputBackend {
  Future<bool> initialize({
    required void Function(String text) onResult,
    required void Function(String message) onError,
    required void Function(String status) onStatus,
  });

  Future<void> startListening({
    required Duration listenFor,
    required Duration pauseFor,
  });

  Future<void> stopListening();

  Future<void> cancelListening();

  void dispose();
}
