import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Wraps an Android foreground service that keeps network connections alive
/// while a chat request is streaming. No-op on iOS and web.
///
/// Android kills background processes and drops WiFi locks aggressively
/// (especially on Samsung devices). A foreground service with a WiFi lock
/// prevents this by promoting the app to foreground priority in the OS
/// scheduler for the duration of the request.
class RequestForegroundService {
  static bool _initialized = false;

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static void init() {
    if (!_supported) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'openchat_request',
        channelName: 'Request in progress',
        channelDescription:
            'Shown while a chat request is running to keep the connection alive.',
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;
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

  static Future<void> start() async {
    if (!_supported || !_initialized) return;
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      serviceId: 1001,
      notificationTitle: 'OpenChat',
      notificationText: 'Waiting for response…',
      callback: _taskCallback,
    );
  }

  static Future<void> stop() async {
    if (!_supported || !_initialized) return;
    await FlutterForegroundTask.stopService();
  }
}

@pragma('vm:entry-point')
void _taskCallback() {
  FlutterForegroundTask.setTaskHandler(_NoOpTaskHandler());
}

class _NoOpTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
