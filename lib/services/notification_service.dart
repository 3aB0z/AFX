import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:io';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../config.dart';

/// Centralized notification system for push and in-app notifications
class NotificationService {
  // Toast display duration
  static const Duration _defaultDuration = Duration(seconds: 3);

  // Flutter Local Notifications plugin instance
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Notification ID constants
  static const int _idMessage = 100;
  static const int _idStatus = 200;
  static const int _idNewRequest = 300;
  static const int _idAccess = 400;

  // Persistence Key
  static const String _keyUnreadPool = 'unread_messages_pool';

  // Firebase Messaging instance
  static FirebaseMessaging? _fcm;

  // Global Navigator Key for deep-linking
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Initialize the notification service
  static Future<void> initialize() async {
    try {
      debugPrint('[NOTIFICATION] 🚀 Initializing notification service...');

      // Initialize FCM only if Firebase is initialized
      try {
        _fcm = FirebaseMessaging.instance;
      } catch (e) {
        debugPrint('[NOTIFICATION] ⚠️ Firebase Messaging not available: $e');
      }

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
        windows: const WindowsInitializationSettings(
          appUserModelId: 'com.android.application.AFX',
          appName: 'AFX',
          guid: '8a7e40ab-7f51-4d46-8b04-d10b808d3384',
        ),
      );

      await _localNotifications.initialize(
        settings,
        onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
      );

      // --- FCM Setup ---
      if (_fcm != null) {
        // Request permission (iOS/Android)
        NotificationSettings fcmSettings = await _fcm!.requestPermission(
          alert: true,
          badge: true,
          provisional: false,
          sound: true,
        );

        debugPrint(
          '[NOTIFICATION] 🔔 FCM Authorization status: ${fcmSettings.authorizationStatus}',
        );

        // Get FCM device token
        String? token = await _fcm!.getToken();
        debugPrint('[NOTIFICATION] 🔑 FCM Token: $token');
        if (token != null) {
          await _saveTokenToFirestore(token);
        }

        // Listen for token refresh
        _fcm!.onTokenRefresh.listen(_saveTokenToFirestore);

        // Listen for foreground messages
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          debugPrint(
            '[NOTIFICATION] 📩 Foreground FCM received: ${message.notification?.title}',
          );
          _handleIncomingMessage(message, isForeground: true);
        });

        // Handle background notification clicks when app is opened from terminated state
        RemoteMessage? initialMessage = await _fcm!.getInitialMessage();
        if (initialMessage != null) {
          _onNotificationTapped(initialMessage.data);
        }

        // Handle background notification clicks when app is in background
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          debugPrint('[NOTIFICATION] 📲 FCM notification opened app');
          _onNotificationTapped(message.data);
        });

        // Subscribe to global chat topic
        await _fcm!.subscribeToTopic('chat_updates');
        debugPrint('[NOTIFICATION] ✅ Subscribed to topic: chat_updates');
      } else {
        debugPrint('[NOTIFICATION] ⚠️ Skipping FCM setup - _fcm is null');
      }
      // --- End FCM Setup ---

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
      debugPrint(
        '[NOTIFICATION] ❌ Error initializing notification service: $e',
      );
    }
  }

  /// Save FCM token to Firestore for targeted notifications
  static Future<void> _saveTokenToFirestore(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'fcm_token': token,
        }, SetOptions(merge: true));
        debugPrint('[NOTIFICATION] 💾 Token saved to Firestore');
      }
    } catch (e) {
      debugPrint('[NOTIFICATION] ❌ Error saving token: $e');
    }
  }

  /// Subscribe to topics based on user role/status
  static Future<void> updateSubscriptions(String role, String status) async {
    if (_fcm == null) return;

    try {
      // Always subscribe to global updates
      await _fcm!.subscribeToTopic('chat_updates');

      // Role based topics
      if (role == 'admin') {
        await _fcm!.subscribeToTopic('admins');
        await _fcm!.unsubscribeFromTopic('non_admins');
      } else {
        await _fcm!.subscribeToTopic('non_admins');
        await _fcm!.unsubscribeFromTopic('admins');
      }

      // Status based topics
      if (status == 'verified' || status == 'approved') {
        await _fcm!.subscribeToTopic('verified_users');
      } else {
        await _fcm!.unsubscribeFromTopic('verified_users');
      }

      debugPrint(
        '[NOTIFICATION] 🔄 Subscriptions updated: role=$role, status=$status',
      );
    } catch (e) {
      debugPrint('[NOTIFICATION] ❌ Error updating subscriptions: $e');
    }
  }

  /// Handle incoming FCM message (foreground/background)
  static void _handleIncomingMessage(
    RemoteMessage message, {
    bool isForeground = false,
  }) {
    final data = message.data;
    final type = data['type'] ?? 'MESSAGE';

    debugPrint('[NOTIFICATION] 📨 Received message of type: $type');

    // Always show local notification for custom actions or foreground display
    _showPushWithActions(
      message.notification?.title ?? data['title'] ?? 'New Notification',
      message.notification?.body ?? data['body'] ?? '',
      data,
    );
  }

  /// Helper for main.dart background handler
  static Future<void> onBackgroundMessage(RemoteMessage message) async {
    final data = message.data;
    await _showPushWithActions(
      message.notification?.title ?? data['title'] ?? 'New Notification',
      message.notification?.body ?? data['body'] ?? '',
      data,
    );
  }

  /// Show notification with action buttons and grouping
  static Future<void> _showPushWithActions(
    String title,
    String body,
    Map<String, dynamic> data,
  ) async {
    final type = data['type'] ?? 'MESSAGE';

    // If app is in foreground and it's a message, suppress
    if (isForeground && type == 'MESSAGE') return;

    try {
      int notifyId = _idMessage;
      String groupKey = 'afx_msg_group';
      List<AndroidNotificationAction>? actions;

      if (type == 'MESSAGE') {
        // --- Grouping Logic ---
        final sender = data['sender_name'] ?? 'User';
        await _addToUnreadPool({
          'sender': sender,
          'content': data['content'] ?? data['body'] ?? body,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });

        final unreadList = await _getUnreadPool();
        final count = unreadList.length;

        if (count > 1) {
          title = '$count New Messages';
          // Create a list of messages for the body
          body = unreadList.reversed
              .take(5) // Show last 5
              .map((m) {
                String c = m['content'] ?? '';
                if (c.length > 35) c = '${c.substring(0, 32)}...';
                return '${m['sender']}: $c';
              })
              .join('\n');
        } else {
          title = '📨 New Message from $sender';
          body = unreadList[0]['content'];
        }

        actions = [
          const AndroidNotificationAction(
            'mark_as_read',
            'Mark as Read',
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ];
      } else if (type == 'STATUS') {
        notifyId = _idStatus;
        groupKey = 'afx_status_group';
      } else if (type == 'NEW_REQUEST') {
        notifyId = _idNewRequest;
        groupKey = 'afx_request_group';
      } else if (type == 'ACCESS') {
        notifyId = _idAccess;
        groupKey = 'afx_access_group';
      }

      final androidDetails = AndroidNotificationDetails(
        'afx_channel',
        'AFX Notifications',
        importance: Importance.max,
        priority: Priority.high,
        groupKey: groupKey,
        setAsGroupSummary: true,
        styleInformation: BigTextStyleInformation(body, contentTitle: title),
        actions: actions,
      );

      final darwinDetails = const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        threadIdentifier: 'afx_thread',
      );

      await _localNotifications.show(
        notifyId,
        title,
        body,
        NotificationDetails(android: androidDetails, iOS: darwinDetails),
        payload: jsonEncode(data),
      );
    } catch (e) {
      debugPrint('[NOTIFICATION] ❌ Error in _showPushWithActions: $e');
    }
  }

  // --- Persistence Helpers ---

  static Future<void> _addToUnreadPool(Map<String, dynamic> msg) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _getUnreadPool();
    list.add(msg);
    await prefs.setString(_keyUnreadPool, jsonEncode(list));
  }

  static Future<List<Map<String, dynamic>>> _getUnreadPool() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_keyUnreadPool);
    if (data == null) return [];
    try {
      final decoded = jsonDecode(data) as List;
      return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> _clearUnreadPool() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUnreadPool);
  }

  /// Handle notification tap/action
  static void _onNotificationTapped(Map<String, dynamic> data) {
    debugPrint(
      '[NOTIFICATION] 📲 Tapping notification of type: ${data['type']}',
    );

    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('[NOTIFICATION] ⚠️ Navigator context not available');
      return;
    }

    final type = data['type'] ?? 'MESSAGE';

    switch (type) {
      case 'MESSAGE':
      case 'ACCESS':
        // Navigate to Chat
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        break;
      case 'STATUS':
        // Navigate to Auth/Home to see status
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        break;
      case 'NEW_REQUEST':
        // Navigate to Requests Page (for admins)
        Navigator.pushNamed(context, '/requests');
        break;
      default:
        debugPrint('[NOTIFICATION] ❓ Unknown notification type: $type');
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

  /// Handle notification response (when user taps on notification or button)
  static void _onDidReceiveNotificationResponse(NotificationResponse response) {
    debugPrint('[NOTIFICATION] 📲 Notification response: ${response.payload}');

    if (response.payload == null) return;

    try {
      final Map<String, dynamic> data = jsonDecode(response.payload!);

      // Handle Action Button
      if (response.actionId == 'mark_as_read') {
        _handleMarkAsRead(data);
        return;
      }

      // Handle Regular Tap
      _onNotificationTapped(data);
    } catch (e) {
      debugPrint('[NOTIFICATION] ❌ Error parsing tapped payload: $e');
    }
  }

  /// Mark all messages as read and clear the pool/notification
  static void _handleMarkAsRead(Map<String, dynamic> data) async {
    debugPrint('[NOTIFICATION] ✅ Actions: Clearing unread message pool');
    await _clearUnreadPool();
    await _localNotifications.cancel(_idMessage);
    showSuccess('All messages marked as read');
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
    debugPrint('[NOTIFICATION] 💬 Message from $senderName');

    // Use the grouped logic for messages
    await _showPushWithActions('📨 New Message', message, {
      'type': 'MESSAGE',
      'sender_name': senderName,
      'content': message,
    });
  }

  /// Show a request status notification
  static Future<void> showRequestStatusNotification(
    String userName,
    String status,
  ) async {
    final statusEmoji = _getStatusEmoji(status);
    debugPrint('[NOTIFICATION] 📋 Request status: $status for $userName');

    // Use the refined logic
    await _showPushWithActions(
      '📋 Request Status Update',
      '$statusEmoji $userName - $status',
      {'type': 'STATUS', 'user_name': userName, 'status': status},
    );
  }

  /// Show new request notification
  static Future<void> showNewRequestNotification(String userName) async {
    debugPrint('[NOTIFICATION] 🆕 New request from $userName');

    // Use the refined logic
    await _showPushWithActions(
      '📋 New Request',
      '📋 New request from $userName',
      {'type': 'NEW_REQUEST', 'user_name': userName},
    );
  }

  /// Show message access changed notification
  static Future<void> showMessageAccessNotification(
    String userName,
    bool canSendMessages,
  ) async {
    final status = canSendMessages ? 'granted' : 'revoked';
    debugPrint('[NOTIFICATION] 🔐 Message access $status for $userName');

    // Use the refined logic
    await _showPushWithActions(
      '🔐 Message Access ${status.toUpperCase()}',
      'Message access $status for $userName',
      {'type': 'ACCESS', 'user_name': userName, 'access_status': status},
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
