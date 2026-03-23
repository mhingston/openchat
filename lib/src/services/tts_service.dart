import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TtsService extends ChangeNotifier {
  TtsService() {
    _init();
  }

  static const String _voiceNameKey = 'openchat.ttsVoiceName';
  static const String _voiceLocaleKey = 'openchat.ttsVoiceLocale';

  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  String? _speakingMessageId;
  List<Map<String, String>> _availableVoices = <Map<String, String>>[];
  String? _selectedVoiceName;

  bool get isSpeaking => _isSpeaking;
  String? get speakingMessageId => _speakingMessageId;
  List<Map<String, String>> get availableVoices =>
      List<Map<String, String>>.unmodifiable(_availableVoices);
  String? get selectedVoiceName => _selectedVoiceName;

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
    _loadVoices();
  }

  Future<void> _loadVoices() async {
    try {
      final dynamic rawVoices = await _tts.getVoices;
      if (rawVoices is List) {
        final List<Map<String, String>> allVoices = rawVoices
            .whereType<Map<dynamic, dynamic>>()
            .map(
              (Map<dynamic, dynamic> v) => <String, String>{
                'name': v['name']?.toString() ?? '',
                'locale': v['locale']?.toString() ?? '',
              },
            )
            .where((Map<String, String> v) => v['name']!.isNotEmpty)
            .toList();

        // Show only voices that match the device locale's language code.
        // Fall back to all voices if none match (e.g. uncommon language).
        final String deviceLanguage =
            PlatformDispatcher.instance.locale.languageCode.toLowerCase();
        final List<Map<String, String>> localeVoices = allVoices
            .where(
              (Map<String, String> v) =>
                  (v['locale'] ?? '').toLowerCase().startsWith(deviceLanguage),
            )
            .toList();
        _availableVoices =
            localeVoices.isNotEmpty ? localeVoices : allVoices;
      }

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? savedName = prefs.getString(_voiceNameKey);
      final String? savedLocale = prefs.getString(_voiceLocaleKey);

      final bool savedVoiceAvailable = savedName != null &&
          savedName.isNotEmpty &&
          _availableVoices.any(
            (Map<String, String> v) => v['name'] == savedName,
          );

      if (savedVoiceAvailable) {
        _selectedVoiceName = savedName;
        await _tts.setVoice(<String, String>{
          'name': savedName,
          'locale': savedLocale ?? '',
        });
      } else if (_availableVoices.isNotEmpty) {
        // No saved voice (or saved voice no longer available) — pick a
        // sensible default: prefer an exact locale match, then first in list.
        final String deviceLocale =
            PlatformDispatcher.instance.locale.toLanguageTag();
        final Map<String, String> defaultVoice = _availableVoices.firstWhere(
          (Map<String, String> v) => v['locale'] == deviceLocale,
          orElse: () => _availableVoices.first,
        );
        _selectedVoiceName = defaultVoice['name'];
        await _tts.setVoice(defaultVoice);
        await prefs.setString(_voiceNameKey, defaultVoice['name']!);
        await prefs.setString(_voiceLocaleKey, defaultVoice['locale']!);
      }

      notifyListeners();
    } catch (_) {
      // Voice loading is best-effort; fall back to system default.
    }
  }

  Future<void> setVoice(String name, String locale) async {
    _selectedVoiceName = name;
    await _tts.setVoice(<String, String>{'name': name, 'locale': locale});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_voiceNameKey, name);
    await prefs.setString(_voiceLocaleKey, locale);
    notifyListeners();
  }

  static String _stripMarkdown(String text) {
    var result = text.replaceAll(RegExp(r'```[\s\S]*?```'), '');
    result = result.replaceAll(RegExp(r'`[^`]*`'), '');
    result = result.replaceAllMapped(
      RegExp(r'\*{1,3}(.*?)\*{1,3}', dotAll: true),
      (Match m) => m.group(1) ?? '',
    );
    result = result.replaceAllMapped(
      RegExp(r'_{1,3}(.*?)_{1,3}', dotAll: true),
      (Match m) => m.group(1) ?? '',
    );
    result = result.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
    result = result.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '');
    result = result.replaceAllMapped(
      RegExp(r'\[([^\]]*)\]\([^)]*\)'),
      (Match m) => m.group(1) ?? '',
    );
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
