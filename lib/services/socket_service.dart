import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import '../config.dart';
import '../auth.dart';
import 'notification_service.dart';

class SocketService {
  static io.Socket? _socket;
  static bool _initialized = false;
  static const MethodChannel _backgroundChannel = MethodChannel(
    'com.example.frontend/notifications',
  );

  // Keep-alive timer for background mode
  static Timer? _keepAliveTimer;

  // Track app foreground state for background service
  static bool _appInForeground = false;

  // Track current user's role for conditional notifications
  static String? _currentUserRole;

  // Callback lists for socket events
  static final List<Function(Map<String, dynamic>)>
  _requestStatusUpdatedCallbacks = [];
  static final List<Function(Map<String, dynamic>)>
  _messageAccessChangedCallbacks = [];
  static final List<Function(Map<String, dynamic>)>
  _adminCountsUpdatedCallbacks = [];
  static final List<Function(Map<String, dynamic>)> _requestUpdatedCallbacks =
      [];
  static final List<Function(Map<String, dynamic>)>
  _requestsAllLoadedCallbacks = [];
  static final List<Function(Map<String, dynamic>)>
  _requestsByStatusLoadedCallbacks = [];
  static final List<Function(Map<String, dynamic>)> _newMessageCallbacks = [];

  static io.Socket get socket {
    if (_socket == null) {
      throw Exception('Socket service not initialized. Call init() first.');
    }
    return _socket!;
  }

  /// Safely disconnect the socket without throwing an error if not initialized
  static Future<void> safeDisconnect() async {
    try {
      if (_socket != null && _socket!.connected) {
        _socket!.disconnect();
        _socket = null;
        _initialized = false;
        debugPrint('[SOCKET] ✅ Socket disconnected safely');
      }
    } catch (e) {
      debugPrint('[SOCKET] Safe disconnect error (ignored): $e');
    }
  }

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    debugPrint('[SOCKET] Initializing socket service...');

    // Set app_in_foreground to true at startup (app is always in foreground initially)
    _appInForeground = true;
    _saveAppForegroundState(true);

    // Save config URL to SharedPreferences for background service (async, non-blocking)
    _saveConfigToPreferences()
        .then((_) {
          debugPrint('[SOCKET] Config saved to SharedPreferences');
        })
        .catchError((e) {
          debugPrint('[SOCKET] Error saving config: $e');
        });

    // Start background service to keep socket alive (async, non-blocking)
    _startBackgroundService()
        .then((_) {
          debugPrint('[SOCKET] Background service started');
        })
        .catchError((e) {
          debugPrint('[SOCKET] Error starting background service: $e');
        });

    debugPrint('[SOCKET] Creating socket connection to ${Config.baseUrl}');

    // Initialize socket connection with timeout and non-blocking
    try {
      _socket = io.io(
        Config.baseUrl,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .setReconnectionAttempts(-1) // Unlimited reconnection attempts
            .setReconnectionDelay(1000)
            .setReconnectionDelayMax(5000)
            .enableAutoConnect()
            .enableForceNew()
            .enableReconnection()
            .setExtraHeaders({'connection': 'keep-alive'})
            .setQuery({'platform': 'mobile', 'backgroundEnabled': 'true'})
            .build(),
      );

      debugPrint('[SOCKET] Socket created, setting up listeners...');
      _setupSocketListeners();

      // Explicitly connect (in case enableAutoConnect() doesn't work)
      _socket!.connect();
      debugPrint('[SOCKET] 🔗 Explicit connect() called');
      debugPrint('[SOCKET] Socket service initialized');

      // Check connection status after a short delay
      Future.delayed(const Duration(milliseconds: 500), () {
        final connected = _socket?.connected ?? false;
        final id = _socket?.id ?? 'unknown';
        debugPrint(
          '[SOCKET] 🔍 Connection check after 500ms - Connected: $connected, ID: $id',
        );
      });

      // Check again after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        final connected = _socket?.connected ?? false;
        final id = _socket?.id ?? 'unknown';
        debugPrint(
          '[SOCKET] 🔍 Connection check after 2s - Connected: $connected, ID: $id',
        );
      });
    } catch (e) {
      debugPrint('[SOCKET] Error creating socket: $e');
      _initialized = false; // Reset on error so retry can happen
      rethrow;
    }
  }

  /// Save config URL to SharedPreferences for background service access
  static Future<void> _saveConfigToPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('config_baseUrl', Config.baseUrl);
      debugPrint(
        '[SOCKET] 💾 Config URL saved to SharedPreferences: ${Config.baseUrl}',
      );
    } catch (e) {
      debugPrint('[SOCKET] ⚠️ Error saving config: $e');
    }
  }

  static Future<void> _startBackgroundService() async {
    try {
      debugPrint('[SOCKET] Starting background service...');
      const platform = MethodChannel('com.example.frontend/socket_background');
      await platform.invokeMethod('startBackgroundService');
      debugPrint('[SOCKET] Background service started successfully');
    } catch (e) {
      debugPrint('[SOCKET] Error starting background service: $e');
    }
  }

  static Future<void> _authenticateSocket() async {
    try {
      debugPrint('[SOCKET] 🔐 Attempting to authenticate socket...');
      final loginData = await Auth.getLogin();
      if (loginData != null) {
        // Store user role for conditional notifications
        _currentUserRole = loginData['role'] as String?;

        // Emit authenticate event with user data
        debugPrint(
          '[SOCKET] 👤 Login data found: email=${loginData['email']}, userId=${loginData['id']}, role=${loginData['role']}',
        );
        emit('register_user', {
          'userId': loginData['id'],
          'email': loginData['email'],
          'role': loginData['role'],
        });
        debugPrint(
          '[SOCKET] ✅ User registered event EMITTED: ${loginData['email']}',
        );

        // Request updated message access status after reconnection
        debugPrint('[SOCKET] 📤 Requesting updated message access status...');
        emit('check_message_access', {'userId': loginData['id']});
      } else {
        debugPrint('[SOCKET] ⚠️ No login data found - user not authenticated');
      }
    } catch (e) {
      debugPrint('[SOCKET] ❌ Error authenticating socket: $e');
    }
  }

  static void _setupSocketListeners() {
    debugPrint('[SOCKET] 🔗 Registering socket event listeners...');

    _socket!.on('connect', (_) async {
      debugPrint('[SOCKET] ✅ CONNECTED - Socket ID: ${_socket!.id}');
      debugPrint('[SOCKET] Socket is connected: ${_socket!.connected}');
      // Authenticate on connect
      await _authenticateSocket();
    });

    _socket!.on('disconnect', (_) {
      debugPrint('[SOCKET] ❌ DISCONNECTED - Socket ID: ${_socket!.id}');
    });

    _socket!.on('reconnect', (_) {
      debugPrint('[SOCKET] 🔄 RECONNECTED - Socket ID: ${_socket!.id}');
      // Authenticate again on reconnect
      _authenticateSocket();
    });

    _socket!.on('reconnect_attempt', (_) {
      debugPrint(
        '[SOCKET] 🔄 RECONNECT ATTEMPT - Attempt ${_socket!.io.reconnectionAttempts!}',
      );
    });

    _socket!.on('connect_error', (error) {
      debugPrint('[SOCKET] ⚠️ CONNECTION ERROR: $error');
    });

    _socket!.on('error', (error) {
      debugPrint('[SOCKET] ⚠️ ERROR: $error');
    });

    _socket!.on('notification', (data) {
      debugPrint(
        '[SOCKET] 📢 Notification received (using only background service): ${data['title']}',
      );
      // Don't show notifications via Flutter - use only background service
    });

    _socket!.on('new_message', (data) {
      debugPrint(
        '[SOCKET] 💬 New message from ${data['sender_name']}: ${data['content']}',
      );

      // Show in-app notification (only works if app is in foreground)
      final senderName = data['sender_name'] ?? 'Someone';
      final content = data['content'] ?? '';
      if (content.isNotEmpty && _appInForeground) {
        unawaited(
          NotificationService.showMessageNotification(senderName, content),
        );
      }

      // Forward to background service to show notification when app is in background
      unawaited(_forwardMessageToBackground(data, 'new_message'));

      final eventData = Map<String, dynamic>.from(data as Map);
      debugPrint(
        '[SOCKET] 🔔 Calling ${_newMessageCallbacks.length} new message callbacks',
      );
      for (final callback in _newMessageCallbacks) {
        callback(eventData);
      }
    });

    _socket!.on('new_request', (data) {
      debugPrint('[SOCKET] 📋 New request from ${data['name']}');
      // Show notification for admin users ALWAYS (foreground and background)
      final isAdmin = _currentUserRole?.toLowerCase() == 'admin';
      if (isAdmin) {
        final userName = data['name'] ?? 'Unknown User';
        unawaited(NotificationService.showNewRequestNotification(userName));
        debugPrint(
          '[SOCKET] 📢 Notification shown to admin (foreground or background)',
        );
      }

      // Forward to background service for background notifications (admin only)
      if (isAdmin && !_appInForeground) {
        unawaited(_forwardMessageToBackground(data, 'new_request'));
      }
      debugPrint(
        '[SOCKET] ⏭️ Notification skipped (${isAdmin ? 'already shown' : 'not admin'})',
      );
    });

    // Request status updates (replaces polling)
    _socket!.on('request_status_updated', (data) {
      debugPrint('[SOCKET] 📊 Request status updated: ${data['status']}');
      // NOT showing in-app notification (removed per request)
      debugPrint('[SOCKET] ⏭️ Notification skipped (request_status_updated)');
      final eventData = Map<String, dynamic>.from(data as Map);
      for (final callback in _requestStatusUpdatedCallbacks) {
        callback(eventData);
      }
    });

    _socket!.on('request_status_not_found', (data) {
      debugPrint('[SOCKET] ❌ Request not found for email: ${data['email']}');
    });

    _socket!.on('request_status_error', (data) {
      debugPrint('[SOCKET] ⚠️ Request status error: ${data['message']}');
    });

    // Message access changes
    _socket!.on('message_access_changed', (data) {
      debugPrint(
        'Message access changed for user ${data['userId']}: ${data['canSendMessages']}',
      );
      // Show in-app notification for NON-ADMIN users only (and only if in foreground)
      final isAdmin = _currentUserRole?.toLowerCase() == 'admin';
      if (!isAdmin && _appInForeground) {
        final userName = data['userName'] ?? 'User ${data['userId']}';
        final canSendMessages = data['canSendMessages'] as bool? ?? false;
        unawaited(
          NotificationService.showMessageAccessNotification(
            userName,
            canSendMessages,
          ),
        );
        debugPrint('[SOCKET] 📢 Notification shown to non-admin');
      }

      // Forward to background service for background notifications (non-admin only)
      if (!isAdmin) {
        unawaited(_forwardMessageToBackground(data, 'message_access_changed'));
      }

      // Don't show notification for access status updates
      final eventData = Map<String, dynamic>.from(data as Map);
      for (final callback in _messageAccessChangedCallbacks) {
        callback(eventData);
      }
    });

    // Admin dashboard updates
    _socket!.on('admin_counts_updated', (data) {
      debugPrint('Admin counts updated: ${data['pending']} pending');
      final eventData = Map<String, dynamic>.from(data as Map);
      for (final callback in _adminCountsUpdatedCallbacks) {
        callback(eventData);
      }
    });

    // Request updates (status changes, edits from any source)
    _socket!.on('request_updated', (data) {
      debugPrint('Request updated: id ${data['id']}');
      final eventData = Map<String, dynamic>.from(data as Map);
      for (final callback in _requestUpdatedCallbacks) {
        callback(eventData);
      }
    });

    // Request verification
    _socket!.on('request_verified', (data) {
      debugPrint('Request verified: ${data['email']}');
    });

    // Request rejection
    _socket!.on('request_rejected', (data) {
      debugPrint('Request rejected: ${data['id']}');
    });

    // All requests loaded (all statuses combined)
    _socket!.on('requests_all_loaded', (data) {
      debugPrint('All requests loaded: page ${data['page']}');
      final eventData = Map<String, dynamic>.from(data as Map);
      for (final callback in _requestsAllLoadedCallbacks) {
        callback(eventData);
      }
    });

    // Requests by status loaded
    _socket!.on('requests_by_status_loaded', (data) {
      debugPrint('Requests loaded for ${data['status']}: page ${data['page']}');
      final eventData = Map<String, dynamic>.from(data as Map);
      for (final callback in _requestsByStatusLoadedCallbacks) {
        callback(eventData);
      }
    });
  }

  static void connect() {
    _socket?.connect();
  }

  static void disconnect() {
    _socket?.disconnect();
  }

  static void emit(String event, dynamic data) {
    try {
      // Ensure data is JSON-encodable
      final encodedData = jsonEncode(data);
      final decodedData = jsonDecode(encodedData);
      _socket?.emit(event, decodedData);
    } catch (e) {
      debugPrint('Socket emit error: Failed to encode data - $e');
    }
  }

  /// Set app foreground state (called by lifecycle observer)
  static void setAppInForeground(bool value) {
    _appInForeground = value;
    debugPrint(
      '[NOTIFICATION] App is now ${_appInForeground ? 'in FOREGROUND' : 'in BACKGROUND'}',
    );
    // Also save to SharedPreferences so Java code can read it
    _saveAppForegroundState(_appInForeground);

    // Clear old cached messages when app comes to foreground
    // This prevents re-displaying messages that were already shown
    if (_appInForeground) {
      _clearCachedMessages();
    }
  }

  /// Clear cached messages from background service when app returns to foreground
  static void _clearCachedMessages() {
    try {
      debugPrint(
        '[NOTIFICATION] 🗑️ Clearing cached messages from background service',
      );
      const platform = MethodChannel('com.example.frontend/notifications');
      platform
          .invokeMethod('clearCachedMessages')
          .then((_) {
            debugPrint('[NOTIFICATION] ✅ Cached messages cleared successfully');
          })
          .catchError((e) {
            debugPrint('[NOTIFICATION] ⚠️ Method not available or error: $e');
          });
    } catch (e) {
      debugPrint('[NOTIFICATION] ⚠️ Error clearing cached messages: $e');
    }
  }

  /// Save app foreground state to SharedPreferences for Java code to read
  static Future<void> _saveAppForegroundState(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('app_in_foreground', value);
      debugPrint(
        '[NOTIFICATION] 💾 Saved app_in_foreground=$value to SharedPreferences',
      );
    } catch (e) {
      debugPrint('[NOTIFICATION] ❌ Error saving app_in_foreground: $e');
    }
  }

  // Listen for request status updates
  static void onRequestStatusUpdated(Function(Map<String, dynamic>) callback) {
    _requestStatusUpdatedCallbacks.add(callback);
  }

  // Listen for message access changes
  static void onMessageAccessChanged(Function(Map<String, dynamic>) callback) {
    _messageAccessChangedCallbacks.add(callback);
  }

  // Listen for admin count updates
  static void onAdminCountsUpdated(Function(Map<String, dynamic>) callback) {
    _adminCountsUpdatedCallbacks.add(callback);
  }

  // Listen for individual request updates (status changes, edits from any source)
  static void onRequestUpdated(Function(Map<String, dynamic>) callback) {
    _requestUpdatedCallbacks.add(callback);
  }

  // Listen for all requests loaded (all statuses)
  static void onRequestsAllLoaded(Function(Map<String, dynamic>) callback) {
    _requestsAllLoadedCallbacks.add(callback);
  }

  // Listen for requests loaded by status
  static void onRequestsByStatusLoaded(
    Function(Map<String, dynamic>) callback,
  ) {
    _requestsByStatusLoadedCallbacks.add(callback);
  }

  // Listen for new messages
  static void onNewMessage(Function(Map<String, dynamic>) callback) {
    debugPrint(
      '[SOCKET] ✅ Registering onNewMessage callback (total: ${_newMessageCallbacks.length + 1})',
    );
    _newMessageCallbacks.add(callback);
  }

  // Join admin dashboard for real-time updates
  static void joinAdminDashboard() {
    emit('join_admin_dashboard', {});
  }

  // Load all requests (all statuses combined)
  static void loadRequestsAll(int page) {
    emit('load_requests_all', {'page': page});
  }

  // Load requests by status
  static void loadRequestsByStatus(String status, int page) {
    emit('load_requests_by_status', {'status': status, 'page': page});
  }

  /// Forward message to background service for notification
  static Future<void> _forwardMessageToBackground(
    dynamic data,
    String eventType,
  ) async {
    try {
      debugPrint(
        '[NOTIFICATION] 📤 Forwarding $eventType to background service...',
      );

      // Add event type to data
      final notificationData = {
        ...?((data as Map?)?.cast<String, dynamic>()),
        'event_type': eventType,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Send message data to background service
      await _backgroundChannel
          .invokeMethod('showBackgroundNotification', notificationData)
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('[NOTIFICATION] ⚠️ Background service call timed out');
            },
          );
      debugPrint('[NOTIFICATION] ✅ $eventType forwarded to background service');
    } on PlatformException catch (e) {
      debugPrint('[NOTIFICATION] ⚠️ Platform error: ${e.code} - ${e.message}');
    } catch (e) {
      debugPrint('[NOTIFICATION] ⚠️ Failed to forward to background: $e');
    }
  }

  /// Start keep-alive timer when app goes to background
  static void startBackgroundKeepAlive() {
    if (_keepAliveTimer != null) return; // Already running

    debugPrint('[SOCKET] 🔄 Starting background keep-alive timer...');
    _keepAliveTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (_socket != null && _socket!.connected) {
        debugPrint('[SOCKET] 💓 Keep-alive ping sent');
        // Send a lightweight ping to keep connection alive
        _socket!.emit('ping', {});
      }
    });
  }

  /// Stop keep-alive timer when app comes to foreground
  static void stopBackgroundKeepAlive() {
    if (_keepAliveTimer != null) {
      _keepAliveTimer!.cancel();
      _keepAliveTimer = null;
      debugPrint('[SOCKET] ⏹️ Stopped background keep-alive timer');
    }
  }

  static void dispose() {
    stopBackgroundKeepAlive();
    _socket?.dispose();
    _socket = null;
    _initialized = false;
  }
}
