import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService extends ChangeNotifier {
  TtsService() {
    _init();
  }

  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  String? _speakingMessageId;

  bool get isSpeaking => _isSpeaking;
  String? get speakingMessageId => _speakingMessageId;

  void _init() {
    _tts.setStartHandler(() {
      _isSpeaking = true;
      notifyListeners();
    });
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      _speakingMessageId = null;
      notifyListeners();
    });
    _tts.setErrorHandler((dynamic message) {
      _isSpeaking = false;
      _speakingMessageId = null;
      notifyListeners();
    });
  }

  static String _stripMarkdown(String text) {
    var result = text.replaceAll(RegExp(r'```[\s\S]*?```'), '');
    result = result.replaceAll(RegExp(r'`[^`]*`'), '');
    result = result.replaceAll(RegExp(r'\*{1,3}(.*?)\*{1,3}'), r'$1');
    result = result.replaceAll(RegExp(r'_{1,3}(.*?)_{1,3}'), r'$1');
    result = result.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
    result = result.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '');
    result = result.replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1');
    result = result.replaceAll(
        RegExp(r'^[-*_]{3,}\s*$', multiLine: true), '');
    result = result.replaceAll(RegExp(r'^>\s+', multiLine: true), '');
    result = result.replaceAll(RegExp(r'^[-*+]\s+', multiLine: true), '');
    result = result.replaceAll(RegExp(r'^\d+\.\s+', multiLine: true), '');
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return result.trim();
  }

  Future<void> speak(String text, {required String messageId}) async {
    if (_speakingMessageId == messageId && _isSpeaking) {
      await stop();
      return;
    }
    await stop();
    _speakingMessageId = messageId;
    notifyListeners();
    await _tts.speak(_stripMarkdown(text));
  }

  Future<void> stop() async {
    await _tts.stop();
    _isSpeaking = false;
    _speakingMessageId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }
}
