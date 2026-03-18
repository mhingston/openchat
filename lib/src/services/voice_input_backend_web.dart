// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:js' as js;

import 'voice_input_backend.dart';

class BrowserVoiceInputBackend implements VoiceInputBackend {
  js.JsObject? _recognition;
  Timer? _listenTimer;
  late void Function(String text) _onResult;
  late void Function(String message) _onError;
  late void Function(String status) _onStatus;

  @override
  Future<bool> initialize({
    required void Function(String text) onResult,
    required void Function(String message) onError,
    required void Function(String status) onStatus,
  }) async {
    _onResult = onResult;
    _onError = onError;
    _onStatus = onStatus;

    final Object? constructor = js.context['SpeechRecognition'] ??
        js.context['webkitSpeechRecognition'];
    if (constructor == null) {
      return false;
    }

    final js.JsObject recognition = js.JsObject(constructor as js.JsFunction)
      ..['continuous'] = false
      ..['interimResults'] = true
      ..['lang'] = 'en-US'
      ..['onresult'] = (dynamic event) {
        final String transcript = _extractTranscript(event);
        if (transcript.isNotEmpty) {
          _onResult(transcript);
        }
      }
      ..['onerror'] = (dynamic event) {
        final String message = _extractError(event);
        _onError(
          message.isEmpty ? 'Speech recognition error.' : message,
        );
      }
      ..['onend'] = (dynamic _) {
        _listenTimer?.cancel();
        _onStatus('notListening');
      };

    _recognition = recognition;
    return true;
  }

  @override
  Future<void> startListening({
    required Duration listenFor,
    required Duration pauseFor,
  }) async {
    final js.JsObject? recognition = _recognition;
    if (recognition == null) {
      throw StateError('Voice input is unavailable.');
    }

    _listenTimer?.cancel();
    recognition.callMethod('start');
    _listenTimer = Timer(listenFor, () {
      recognition.callMethod('stop');
      _onStatus('done');
    });
  }

  @override
  Future<void> stopListening() async {
    _listenTimer?.cancel();
    _recognition?.callMethod('stop');
  }

  @override
  Future<void> cancelListening() async {
    _listenTimer?.cancel();
    _recognition?.callMethod('abort');
    _onStatus('notListening');
  }

  @override
  void dispose() {
    _listenTimer?.cancel();
    _recognition?.callMethod('abort');
  }

  String _extractTranscript(dynamic event) {
    try {
      final dynamic results = _getProperty(event, 'results');
      final int length = _toInt(_getProperty(results, 'length'));
      final StringBuffer buffer = StringBuffer();
      for (int index = 0; index < length; index += 1) {
        final dynamic result = _getProperty(results, index);
        final dynamic alternative = _getProperty(result, 0);
        final String transcript =
            (_getProperty(alternative, 'transcript') as String? ?? '').trim();
        if (transcript.isNotEmpty) {
          if (buffer.isNotEmpty) {
            buffer.write(' ');
          }
          buffer.write(transcript);
        }
      }
      return buffer.toString();
    } on Object {
      return '';
    }
  }

  String _extractError(dynamic event) {
    try {
      final String error =
          (_getProperty(event, 'error') as String? ?? '').trim();
      if (error.isEmpty) {
        return '';
      }
      return switch (error) {
        'network' =>
          'Voice input could not reach the browser speech service. Try Chrome or Edge, confirm you are online, and then try again.',
        'not-allowed' ||
        'service-not-allowed' =>
          'Microphone access is blocked. Allow microphone access in your browser and try again.',
        'no-speech' =>
          'No speech was detected. Try again and speak a little closer to the microphone.',
        'audio-capture' =>
          'No microphone was found. Check your audio input device and try again.',
        'aborted' => 'Voice input was cancelled.',
        _ => 'Speech recognition error: $error',
      };
    } on Object {
      return '';
    }
  }

  dynamic _getProperty(dynamic target, Object key) {
    if (target == null) {
      return null;
    }
    final Object browserTarget = target as Object;
    final js.JsObject object = browserTarget is js.JsObject
        ? browserTarget
        : js.JsObject.fromBrowserObject(browserTarget);
    return object[key];
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }
}

VoiceInputBackend createVoiceInputBackend() => BrowserVoiceInputBackend();
