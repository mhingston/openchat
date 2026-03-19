import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Manages the native Android [KeepAliveService] that holds WiFi and wake
/// locks while a streaming chat request is in progress.
///
/// The service calls [startForeground()] with explicit [foregroundServiceType]
/// flags (required on Android 14+/API 34+). Using a direct native
/// implementation avoids the third-party plugin calling [startForeground()]
/// without service types, which Android kills after a 5-second timeout.
///
/// Notification permission is requested natively by [MainActivity.onResume()]
/// using [ActivityResultLauncher] — no Flutter plugin required.
///
/// No-op on iOS and web.
class RequestForegroundService {
  static const MethodChannel _channel =
      MethodChannel('com.mhingston.openchat/keep_alive');

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static void init() {
    // Retained for call-site compatibility; no initialisation required.
  }

  /// No-op — permission is now requested natively in MainActivity.onResume().
  static Future<void> requestPermissions() async {}

  /// Returns true if the notification permission required to run a foreground
  /// service has been granted (or is not required on this platform).
  static Future<bool> hasNotificationPermission() async {
    if (!_supported) return true;
    try {
      final granted =
          await _channel.invokeMethod<bool>('hasNotificationPermission');
      return granted ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Starts the native [KeepAliveService]. Returns false if the notification
  /// permission has not been granted — callers should warn the user.
  static Future<bool> start() async {
    if (!_supported) return true;
    if (!await hasNotificationPermission()) return false;
    try {
      await _channel.invokeMethod<void>('start');
    } catch (_) {}
    return true;
  }

  static Future<void> stop() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
