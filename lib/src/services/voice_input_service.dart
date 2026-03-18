import 'package:flutter/foundation.dart';

import 'voice_input_backend.dart';
import 'voice_input_backend_stub.dart'
    if (dart.library.js_interop) 'voice_input_backend_web.dart' as backend_impl;

const Object _voiceInputStateUnchanged = Object();

enum VoiceInputStatus { idle, initializing, listening, error }

@immutable
class VoiceInputState {
  const VoiceInputState({
    required this.status,
    this.transcribedText = '',
    this.errorMessage,
    this.isAvailable = false,
  });

  final VoiceInputStatus status;
  final String transcribedText;
  final String? errorMessage;
  final bool isAvailable;

  VoiceInputState copyWith({
    VoiceInputStatus? status,
    String? transcribedText,
    Object? errorMessage = _voiceInputStateUnchanged,
    bool? isAvailable,
  }) {
    return VoiceInputState(
      status: status ?? this.status,
      transcribedText: transcribedText ?? this.transcribedText,
      errorMessage: identical(errorMessage, _voiceInputStateUnchanged)
          ? this.errorMessage
          : errorMessage as String?,
      isAvailable: isAvailable ?? this.isAvailable,
    );
  }

  bool get isListening => status == VoiceInputStatus.listening;
  bool get hasError => status == VoiceInputStatus.error;
}

class VoiceInputService extends ChangeNotifier {
  VoiceInputService()
      : _state = const VoiceInputState(status: VoiceInputStatus.idle),
        _backend = backend_impl.createVoiceInputBackend() {
    _initialize();
  }

  /// Creates a service with a predetermined [VoiceInputState]. For tests only.
  @visibleForTesting
  VoiceInputService.withState(VoiceInputState initialState)
      : _state = initialState,
        _backend = backend_impl.createVoiceInputBackend();

  VoiceInputState _state;
  final VoiceInputBackend _backend;

  VoiceInputState get state => _state;
  bool get isListening => _state.isListening;
  bool get isAvailable => _state.isAvailable;

  /// Replaces the internal state and notifies listeners. For tests only.
  @visibleForTesting
  void forceStateForTest(VoiceInputState newState) {
    _state = newState;
    notifyListeners();
  }

  Future<void> _initialize() async {
    _state = _state.copyWith(status: VoiceInputStatus.initializing);
    notifyListeners();

    try {
      final bool available = await _backend.initialize(
        onResult: _onResult,
        onError: _onError,
        onStatus: _onStatus,
      );
      _state = _state.copyWith(
        status: VoiceInputStatus.idle,
        isAvailable: available,
        errorMessage:
            available ? null : 'Voice input is unavailable on this platform.',
      );
    } on Object {
      _state = _state.copyWith(
        status: VoiceInputStatus.error,
        isAvailable: false,
        errorMessage: 'Could not initialise speech recognition.',
      );
    }

    notifyListeners();
  }

  void _onError(String error) {
    _state = _state.copyWith(
      status: VoiceInputStatus.error,
      errorMessage: error,
    );
    notifyListeners();
  }

  void _onStatus(String status) {
    if ((status == 'notListening' || status == 'done') && _state.isListening) {
      _state = _state.copyWith(status: VoiceInputStatus.idle);
      notifyListeners();
    }
  }

  /// Starts listening for speech. Returns `false` if unavailable or already
  /// listening. Partial results update [VoiceInputState.transcribedText] in
  /// real time so callers can populate a text field immediately.
  Future<bool> startListening({
    Duration listenFor = const Duration(seconds: 30),
    Duration pauseFor = const Duration(seconds: 3),
  }) async {
    if (!_state.isAvailable) return false;
    if (_state.isListening) await stopListening();

    _state = _state.copyWith(
      status: VoiceInputStatus.listening,
      transcribedText: '',
      errorMessage: null,
    );
    notifyListeners();

    try {
      await _backend.startListening(
        listenFor: listenFor,
        pauseFor: pauseFor,
      );
      return true;
    } on Object catch (error) {
      _state = _state.copyWith(
        status: VoiceInputStatus.error,
        errorMessage: 'Failed to start listening: $error',
      );
      notifyListeners();
      return false;
    }
  }

  /// Stops listening and preserves the current transcription.
  Future<void> stopListening() async {
    if (!_state.isListening) return;
    try {
      await _backend.stopListening();
    } on Object {
      // Ignore stop errors; state is corrected below.
    }
    _state = _state.copyWith(status: VoiceInputStatus.idle);
    notifyListeners();
  }

  /// Cancels listening and discards any transcription.
  Future<void> cancelListening() async {
    if (!_state.isListening) return;
    try {
      await _backend.cancelListening();
    } on Object {
      // Ignore cancel errors.
    }
    _state = _state.copyWith(
      status: VoiceInputStatus.idle,
      transcribedText: '',
    );
    notifyListeners();
  }

  void _onResult(String transcript) {
    _state = _state.copyWith(
      transcribedText: transcript,
      errorMessage: null,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _backend.dispose();
    super.dispose();
  }
}
