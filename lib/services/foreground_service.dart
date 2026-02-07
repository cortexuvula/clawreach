import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Manages an Android foreground service that keeps the node WebSocket alive
/// when the app is closed/backgrounded. Shows a persistent notification.
class ForegroundServiceManager {
  static bool _initialized = false;
  static bool _running = false;

  static bool get isRunning => _running;

  /// Initialize the foreground task configuration. Call once at app start.
  static void init() {
    if (_initialized) return;
    _initialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'clawreach_connection',
        channelName: 'ClawReach Connection',
        channelDescription: 'Keeps gateway connection alive in background',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(60000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Start the foreground service. Returns true on success.
  static Future<bool> start() async {
    if (_running) return true;

    debugPrint('🔧 Starting foreground service...');

    // Request notification permission (Android 13+)
    final notifPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    debugPrint('🔧 Notification permission: $notifPermission');
    if (notifPermission != NotificationPermission.granted) {
      debugPrint('🔧 Requesting notification permission...');
      final granted = await FlutterForegroundTask.requestNotificationPermission();
      debugPrint('🔧 Notification permission granted: $granted');
      if (granted != NotificationPermission.granted) {
        debugPrint('❌ Notification permission denied - cannot start service');
        return false;
      }
    }

    // Check battery optimization exemption
    final isBatteryOptimized = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    debugPrint('🔧 Battery optimization exemption: $isBatteryOptimized');
    if (!isBatteryOptimized) {
      debugPrint('🔧 Requesting battery optimization exemption...');
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    debugPrint('🔧 Attempting to start service...');
    final result = await FlutterForegroundTask.startService(
      notificationTitle: 'ClawReach connected',
      notificationText: 'Maintaining gateway connection',
      serviceId: 256,
      callback: _startCallback,
    );

    if (result is ServiceRequestSuccess) {
      _running = true;
      debugPrint('✅ Foreground service started successfully');
      return true;
    } else {
      debugPrint('❌ Foreground service failed to start: $result');
      return false;
    }
  }

  /// Stop the foreground service.
  static Future<void> stop() async {
    if (!_running) return;
    await FlutterForegroundTask.stopService();
    _running = false;
    debugPrint('🔧 Foreground service stopped');
  }

  /// Update the notification text (e.g., connection status).
  static Future<void> updateNotification({
    String? title,
    String? text,
  }) async {
    if (!_running) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: title ?? 'ClawReach connected',
      notificationText: text ?? 'Maintaining gateway connection',
    );
  }
}

// This must be a top-level function for the isolate callback
@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_ConnectionTaskHandler());
}

/// Task handler running in the foreground service.
/// The actual WebSocket is maintained by the main app — this service
/// just keeps the process alive and prevents Android from killing it.
class _ConnectionTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('🔧 [FG] Task started at $timestamp by $starter');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Periodic heartbeat — keeps the service alive.
    // The main app handles actual WebSocket connection.
    debugPrint('🔧 [FG] Heartbeat at $timestamp');
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('🔧 [FG] Task destroyed at $timestamp');
  }

  @override
  void onReceiveData(Object data) {
    debugPrint('🔧 [FG] Received data: $data');
  }

  @override
  void onNotificationButtonPressed(String id) {
    debugPrint('🔧 [FG] Notification button pressed: $id');
  }

  @override
  void onNotificationDismissed() {
    debugPrint('🔧 [FG] Notification dismissed');
  }

  @override
  void onNotificationPressed() {
    debugPrint('🔧 [FG] Notification pressed — bringing app to foreground');
    FlutterForegroundTask.launchApp();
  }
}
