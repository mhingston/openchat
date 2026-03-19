import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Manages the native Android [KeepAliveService] that holds WiFi and wake
/// locks while a streaming chat request is in progress.
///
/// The service calls [startForeground()] with explicit [foregroundServiceType]
/// flags (required on Android 14+/API 34+). Using a direct native
/// implementation avoids the third-party plugin calling [startForeground()]
/// without service types, which Android kills after a 5-second timeout.
///
/// No-op on iOS and web.
class RequestForegroundService {
  static const MethodChannel _channel =
      MethodChannel('com.mhingston.openchat/keep_alive');

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static void init() {
    // flutter_foreground_task is retained only for notification permission
    // utilities; we no longer use it to start the actual service.
  }

  /// Request notification permission (required on Android 13+).
  /// Should be called once after the first frame is rendered.
  static Future<void> requestPermissions() async {
    if (!_supported) return;
    final NotificationPermission permission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  /// Returns true if the notification permission required to run a foreground
  /// service has been granted (or is not required on this platform).
  static Future<bool> hasNotificationPermission() async {
    if (!_supported) return true;
    return await FlutterForegroundTask.checkNotificationPermission() ==
        NotificationPermission.granted;
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
