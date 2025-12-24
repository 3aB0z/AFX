import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:io';
import '../config.dart';

/// Centralized notification system for push and in-app notifications
class NotificationService {
  // Toast display duration
  static const Duration _defaultDuration = Duration(seconds: 3);

  // Flutter Local Notifications plugin instance
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Notification ID counter
  static int _notificationId = 0;

  /// Initialize the notification service
  static Future<void> initialize() async {
    try {
      debugPrint('[NOTIFICATION] 🚀 Initializing notification service...');

      // Android initialization
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/launcher_icon');

      // iOS initialization
      final DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
          );

      final InitializationSettings settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(
        settings,
        onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
      );

      // Create Android notification channel
      if (Platform.isAndroid) {
        await _createAndroidNotificationChannel();
      }

      // Request notification permissions
      if (Platform.isAndroid) {
        await Permission.notification.request();
      }

      debugPrint('[NOTIFICATION] ✅ Notification service initialized');
    } catch (e) {
      debugPrint('[NOTIFICATION] ❌ Error initializing notification service: $e');
    }
  }

  /// Create Android notification channel (required for Android 8+)
  static Future<void> _createAndroidNotificationChannel() async {
    try {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _localNotifications
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();

      if (androidImplementation == null) {
        debugPrint('[NOTIFICATION] ⚠️ Android implementation not available');
        return;
      }

      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'afx_channel',
        'AFX Notifications',
        description: 'Default notification channel for AFX',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
      );

      await androidImplementation.createNotificationChannel(channel);

      debugPrint('[NOTIFICATION] ✅ Android notification channel created');
    } catch (e) {
      debugPrint('[NOTIFICATION] ⚠️ Error creating notification channel: $e');
    }
  }

  /// Handle notification response (when user taps on notification)
  static void _onDidReceiveNotificationResponse(NotificationResponse response) {
    debugPrint('[NOTIFICATION] 📲 Notification tapped: ${response.payload}');
  }

  /// Request notification permissions from user
  static Future<bool> requestNotificationPermission() async {
    try {
      debugPrint('[NOTIFICATION] 🔔 Requesting notification permission...');

      final status = await Permission.notification.request();

      debugPrint('[NOTIFICATION] 📱 Permission status: ${status.name}');

      if (status.isDenied) {
        debugPrint('[NOTIFICATION] ⚠️ Notification permission denied');
        return false;
      } else if (status.isGranted) {
        debugPrint('[NOTIFICATION] ✅ Notification permission granted');
        return true;
      } else if (status.isPermanentlyDenied) {
        debugPrint(
          '[NOTIFICATION] ❌ Notification permission permanently denied - open app settings',
        );
        openAppSettings();
        return false;
      }
      return false;
    } catch (e) {
      debugPrint('[NOTIFICATION] ❌ Error requesting permission: $e');
      return false;
    }
  }

  /// Check if notification permission is already granted
  static Future<bool> isNotificationPermissionGranted() async {
    try {
      final status = await Permission.notification.status;
      debugPrint(
        '[NOTIFICATION] 📋 Notification permission status: ${status.name}',
      );
      return status.isGranted;
    } catch (e) {
      debugPrint('[NOTIFICATION] ❌ Error checking permission: $e');
      return false;
    }
  }

  // App lifecycle state tracking
  static bool isForeground = true;

  /// Show a push notification (works in foreground and background)
  static Future<void> _showPushNotification(
    String title,
    String body, {
    String? payload,
  }) async {
    // If app is in foreground, don't show notification
    if (isForeground) {
      debugPrint('[NOTIFICATION] 🔕 App is in foreground, suppressing notification: $title');
      return;
    }

    try {
      debugPrint('[NOTIFICATION] 📤 Showing push notification: $title');

      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            'afx_channel',
            'AFX Notifications',
            channelDescription: 'Default notification channel for AFX',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            styleInformation: BigTextStyleInformation(body),
          );

      final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        _notificationId++,
        title,
        body,
        notificationDetails,
        payload: payload,
      );
    } catch (e) {
      debugPrint('[NOTIFICATION] ❌ Error showing push notification: $e');
    }
  }

  /// Show an in-app toast notification (foreground only)
  /// Type: 'success' (green), 'error' (red), 'warning' (orange), 'info' (blue)
  static Future<void> showToast(
    String message, {
    String type = 'info',
    Duration duration = _defaultDuration,
  }) async {
    try {
      final Color backgroundColor = _getToastColor(type);

      debugPrint(
        '[NOTIFICATION] 📱 Showing ${type.toUpperCase()} toast: $message',
      );

      await Fluttertoast.showToast(
        msg: message,
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: backgroundColor,
        textColor: Colors.white,
        fontSize: 16.0,
      );
    } catch (e) {
      debugPrint('[NOTIFICATION] ❌ Error showing toast: $e');
    }
  }

  /// Show a success toast
  static Future<void> showSuccess(String message) async {
    await showToast(message, type: 'success');
  }

  /// Show an error toast
  static Future<void> showError(String message) async {
    await showToast(message, type: 'error');
  }

  /// Show a warning toast
  static Future<void> showWarning(String message) async {
    await showToast(message, type: 'warning');
  }

  /// Show an info toast
  static Future<void> showInfo(String message) async {
    await showToast(message, type: 'info');
  }

  // ============================================================================
  // Public Notification Methods (Push Notifications Only - Work in All States)
  // ============================================================================

  /// Show a message received notification
  static Future<void> showMessageNotification(
    String senderName,
    String message,
  ) async {
    final notification = '$senderName: $message';
    debugPrint('[NOTIFICATION] 💬 Message from $senderName');

    // Show push notification only (works in foreground and background)
    await _showPushNotification(
      '📨 New Message',
      notification,
      payload: 'message:$senderName',
    );
  }

  /// Show a request status notification
  static Future<void> showRequestStatusNotification(
    String userName,
    String status,
  ) async {
    final statusEmoji = _getStatusEmoji(status);
    final notification = '$statusEmoji $userName - $status';
    debugPrint('[NOTIFICATION] 📋 Request status: $status for $userName');

    // Show push notification only (works in foreground and background)
    await _showPushNotification(
      '📋 Request Status Update',
      notification,
      payload: 'request:$userName:$status',
    );
  }

  /// Show new request notification
  static Future<void> showNewRequestNotification(String userName) async {
    final notification = '📋 New request from $userName';
    debugPrint('[NOTIFICATION] 🆕 New request from $userName');

    // Show push notification only (works in foreground and background)
    await _showPushNotification(
      '📋 New Request',
      notification,
      payload: 'new_request:$userName',
    );
  }

  /// Show message access changed notification
  static Future<void> showMessageAccessNotification(
    String userName,
    bool canSendMessages,
  ) async {
    final status = canSendMessages ? 'granted' : 'revoked';
    final notification = 'Message access $status for $userName';
    debugPrint('[NOTIFICATION] 🔐 Message access $status for $userName');

    // Show push notification only (works in foreground and background)
    await _showPushNotification(
      '🔐 Message Access ${status.toUpperCase()}',
      notification,
      payload: 'access:$userName:$status',
    );
  }

  /// Get toast background color
  static Color _getToastColor(String type) {
    switch (type.toLowerCase()) {
      case 'success':
        return const Color(0xFF10B981); // Green
      case 'error':
        return const Color(0xFFEF4444); // Red
      case 'warning':
        return const Color(0xFFF59E0B); // Orange
      case 'info':
      default:
        return Config.primaryColor; // Blue
    }
  }

  /// Get status emoji
  static String _getStatusEmoji(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return '⏳';
      case 'verified':
      case 'approved':
        return '✅';
      case 'rejected':
        return '❌';
      default:
        return '📋';
    }
  }
}
