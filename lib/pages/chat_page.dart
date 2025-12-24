// lib/pages/chat_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';
import '../auth.dart';
import '../services/supabase_service.dart';
import '../services/socket_service.dart';
import '../services/notification_service.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/messages_list.dart';
import '../widgets/message_input.dart';
import 'auth_page.dart';
import 'dart:async';

/// Strongly-typed Message class to prevent runtime issues with Map-based data
class Message {
  final dynamic id; // Can be int or String from server
  final int senderId;
  final String senderName;
  final String content;
  final String role;
  final DateTime createdAt;
  final String status; // 'Sending', 'Sent', 'Delivered', 'Read', 'Failed'
  final String? clientId; // Temporary ID for optimistic updates
  final int? prevSenderId;
  final int? nextSenderId;

  Message({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.role,
    required this.createdAt,
    this.status = 'Sent',
    this.clientId,
    this.prevSenderId,
    this.nextSenderId,
  });

  /// Convert from Map (API response) to Message object
  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'] ?? '',
      senderId: map['sender_id'] ?? 0,
      senderName: map['sender_name'] ?? 'User',
      content: map['content'] ?? '',
      role: map['role'] ?? 'user',
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at']).toLocal()
          : DateTime.now(),
      status: map['status'] ?? 'Sent',
      clientId: map['clientId'],
      prevSenderId: map['prev_sender_id'],
      nextSenderId: map['next_sender_id'],
    );
  }

  /// Convert Message object back to Map (for API requests/socket emit)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sender_id': senderId,
      'sender_name': senderName,
      'content': content,
      'role': role,
      'created_at': createdAt.toIso8601String(),
      'status': status,
      'clientId': clientId,
      'prev_sender_id': prevSenderId,
      'next_sender_id': nextSenderId,
    };
  }

  /// Create a copy with modified fields (for updates)
  Message copyWith({
    dynamic id,
    int? senderId,
    String? senderName,
    String? content,
    String? role,
    DateTime? createdAt,
    String? status,
    String? clientId,
    int? prevSenderId,
    int? nextSenderId,
  }) {
    return Message(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      content: content ?? this.content,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      clientId: clientId ?? this.clientId,
      prevSenderId: prevSenderId ?? this.prevSenderId,
      nextSenderId: nextSenderId ?? this.nextSenderId,
    );
  }
}

class AnimatedMessageItem extends StatefulWidget {
  final Widget child;
  final int index;
  final int totalItems;
  final bool isNewMessage;
  final bool isOldMessage;
  final bool isCurrentUser;

  const AnimatedMessageItem({
    required this.child,
    required this.index,
    required this.totalItems,
    this.isNewMessage = false,
    this.isOldMessage = false,
    this.isCurrentUser = false,
    super.key,
  });

  @override
  State<AnimatedMessageItem> createState() => _AnimatedMessageItemState();
}

class _AnimatedMessageItemState extends State<AnimatedMessageItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _setupAnimation();
  }

  void _setupAnimation() {
    if (widget.isNewMessage) {
      // New message animation: slide from sender side with opacity
      final double beginOffset = widget.isCurrentUser ? 100 : -100;

      _slideAnimation = Tween<double>(
        begin: beginOffset,
        end: 0,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

      _opacityAnimation = Tween<double>(
        begin: 0,
        end: 1,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    } else if (widget.isOldMessage) {
      // Old message animation when new message arrives: push downward
      _slideAnimation = Tween<double>(
        begin: 50,
        end: 0,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

      _opacityAnimation = Tween<double>(
        begin: 1,
        end: 1,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    } else {
      // No animation - idle state
      _slideAnimation = Tween<double>(
        begin: 0,
        end: 0,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

      _opacityAnimation = Tween<double>(
        begin: 1,
        end: 1,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    }

    // Reset and start animation
    _controller.reset();
    _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedMessageItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If animation state changed, reset animation with new setup
    if (oldWidget.isNewMessage != widget.isNewMessage ||
        oldWidget.isOldMessage != widget.isOldMessage) {
      _setupAnimation();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (widget.isNewMessage) {
          // New message: slide from side with opacity fade-in
          return Transform.translate(
            offset: Offset(_slideAnimation.value, 0),
            child: Opacity(opacity: _opacityAnimation.value, child: child),
          );
        } else if (widget.isOldMessage) {
          // Old message: slide down when new message arrives
          return Transform.translate(
            offset: Offset(0, _slideAnimation.value),
            child: child,
          );
        } else {
          // No animation
          return child!;
        }
      },
      child: widget.child,
    );
  }
}

class ChatPage extends StatefulWidget {
  final int userId;
  final String userName;
  final String userEmail;
  final String userRole; // 'admin' or 'user'
  const ChatPage({
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.userRole,
    super.key,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with TickerProviderStateMixin {
  final baseUrl = Config.baseUrl;
  final List<Map<String, dynamic>> _messages = [];
  late AnimationController _badgeAnimController; // Animation for badge pulse
  dynamic _lastAnimatedMessageId; // Track which message we just animated
  final controller = TextEditingController();

  // GlobalKey to access MessagesList state for targeted message updates and animations
  final GlobalKey<MessagesListState> _messagesListKey =
      GlobalKey<MessagesListState>();

  // Message queue for sequential sending (local, pending messages shown as loading)
  final List<Map<String, dynamic>> _messageQueue = [];
  bool _isProcessingQueue = false;

  // Queue messages currently being processed (for display as loading)
  final List<Map<String, dynamic>> _queueMessages = [];

  bool _isLoadingMoreMessages = false;
  bool _hasMoreMessages = true;
  int _messagesPage = 0;
  bool _canSendMessages = true; // Track if user can send messages
  bool _accessCheckComplete = false; // Track if access check is done
  int _pendingRequestsCount = 0; // Track pending requests count
  RealtimeChannel? _messagesChannel; // Supabase Realtime channel for messages

  // Queue for processing realtime styling updates sequentially
  final List<Map<String, dynamic>> _realtimeUpdateQueue = [];
  bool _isProcessingRealtimeUpdates = false;

  // Auto-retry mechanism for failed message loading
  Timer? _autoRetryTimer;
  static const Duration _autoRetryInterval = Duration(seconds: 10);
  bool _isAutoRetryActive = false;

  final ScrollController _messagesScrollController = ScrollController();

  List<Map<String, dynamic>> get messages => _messages;

  @override
  void initState() {
    super.initState();
    debugPrint(
      '[CHAT_PAGE] 📱 initState called for user: ${widget.userName} (role: ${widget.userRole})',
    );

    // Initialize animation controller for badge pulse animation
    _badgeAnimController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _messagesScrollController.addListener(_onMessagesScroll);
    loadMessages();
    _setupSupabaseRealtimeListeners();

    // For non-admins, check message access from Supabase
    if (widget.userRole != 'admin') {
      debugPrint(
        '[CHAT_PAGE] 👤 User role is not admin, checking message access',
      );
      checkMessageAccess();
    } else {
      debugPrint(
        '[CHAT_PAGE] 👨‍💼 User role is ADMIN, fetching pending requests',
      );
      // Admins can always send messages
      setState(() {
        _canSendMessages = true;
        _accessCheckComplete = true;
      });
      // Fetch pending requests count for admins
      _fetchPendingRequestsCount();
      // Start badge animation for pending requests
      _badgeAnimController.repeat();
      debugPrint('[CHAT_PAGE] ▶️ Badge animation started');
    }
  }

  /// Set up Supabase Realtime listeners for messages and status changes
  Future<void> _setupSupabaseRealtimeListeners() async {
    debugPrint('[CHAT] 📡 Setting up Supabase Realtime listeners');

    try {
      // Subscribe to new messages in real-time
      _messagesChannel = SupabaseService.subscribeToMessages(
        (newMessage) {
          // Handle new message insert
          debugPrint(
            '[CHAT] 🆕 New message received: ${newMessage['content']}',
          );
          _handleNewMessage(newMessage);
        },
        (updatedMessage) {
          // Handle message update (e.g., prev/next_sender_id changed by trigger)
          debugPrint('[CHAT] ✏️ Message updated: ${updatedMessage['id']}');
          _updateMessageById(updatedMessage['id'], updatedMessage);
        },
        (deletedMessage) {
          // Handle message delete
          debugPrint('[CHAT] 🗑️ Message deleted: ${deletedMessage['id']}');
          _deleteMessageById(deletedMessage['id']);
        },
      );
    } catch (e) {
      debugPrint('[CHAT] ⚠️ Error setting up Realtime listeners: $e');
    }
  }

  /// Update a specific message by ID (skips current user's messages)
  /// Called when database triggers update adjacent messages
  void _updateMessageById(dynamic messageId, Map<String, dynamic> updatedData) {
    // Skip updates from current user - their messages are handled differently
    if (updatedData['sender_id'] == widget.userId) {
      debugPrint(
        '[REALTIME] ⏭️ Skipping update for current user message (ID=$messageId)',
      );
      return;
    }

    if (!mounted) {
      debugPrint('[REALTIME] ⚠️ Widget not mounted, skipping message update');
      return;
    }

    setState(() {
      final index = _messages.indexWhere((msg) => msg['id'] == messageId);

      if (index >= 0) {
        debugPrint('[REALTIME] 🔄 Updating message $messageId at index $index');
        debugPrint(
          '[REALTIME] 📊 New prev_sender_id: ${updatedData['prev_sender_id']}, '
          'New next_sender_id: ${updatedData['next_sender_id']}',
        );

        // Update only the changed fields while preserving other data
        _messages[index] = {..._messages[index], ...updatedData};
      } else {
        debugPrint('[REALTIME] ⚠️ Message $messageId not found in list');
      }
    });
  }

  /// Delete a specific message by ID (removes from UI)
  void _deleteMessageById(dynamic messageId) {
    if (!mounted) {
      debugPrint('[REALTIME] ⚠️ Widget not mounted, skipping message delete');
      return;
    }

    setState(() {
      final index = _messages.indexWhere((msg) => msg['id'] == messageId);

      if (index >= 0) {
        debugPrint('[REALTIME] 🗑️ Removing message $messageId from UI');
        _messages.removeAt(index);
      } else {
        debugPrint('[REALTIME] ⚠️ Message $messageId not found in list');
      }
    });
  }

  /// Handle new message from Supabase Realtime
  Future<void> _handleNewMessage(Map<String, dynamic> messageData) async {
    debugPrint(
      '[REALTIME] 📨 _handleNewMessage called with: ${messageData['content']}',
    );
    final incomingMessage = Map<String, dynamic>.from(messageData);

    // CURRENT USER - Update existing message with trigger data
    if (incomingMessage['sender_id'] == widget.userId) {
      debugPrint(
        '[REALTIME] Current user msg - updating existing (senderId=${widget.userId})',
      );
      final idx = _messages.indexWhere(
        (msg) => msg['id'] == incomingMessage['id'],
      );
      if (idx >= 0) {
        // Update data directly without setState
        _messages[idx] = {
          ..._messages[idx],
          ...incomingMessage,
          'status': 'Sent',
          'clientId': null,
        };

        // Trigger rebuild ONLY for this specific message
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final messageId = _messages[idx]['id'] ?? _messages[idx]['clientId'];
          _messagesListKey.currentState?.updateMessageById(messageId);

          // Also trigger rebuild for previous message if it exists (its next_sender_id changed)
          if (idx + 1 < _messages.length) {
            final prevMessageId =
                _messages[idx + 1]['id'] ?? _messages[idx + 1]['clientId'];
            _messagesListKey.currentState?.updateMessageById(prevMessageId);
          }
        });
      }
      return;
    }

    debugPrint('[REALTIME]  Checking incoming message: $incomingMessage');

    // Trigger now populates sender_name, prev_sender_id, next_sender_id
    // Set defaults in case any are missing
    incomingMessage['sender_name'] ??= 'User';
    incomingMessage['status'] ??= 'Sent';

    // Fetch role if missing (critical for admin styles)
    if (incomingMessage['role'] == null) {
      try {
        debugPrint('[REALTIME] 🔍 Fetching role for user ${incomingMessage['sender_id']}');
        final userResponse = await SupabaseService.supabase
            .from('users')
            .select('role, name')
            .eq('id', incomingMessage['sender_id'])
            .single();
        
        if (userResponse != null) {
          incomingMessage['role'] = userResponse['role'];
          debugPrint('[REALTIME] ✅ Fetched role: ${incomingMessage['role']}');
          
          // Also update name if it was just 'User'
          if (incomingMessage['sender_name'] == 'User' && userResponse['name'] != null) {
            incomingMessage['sender_name'] = userResponse['name'];
          }
        }
      } catch (e) {
        debugPrint('[REALTIME] ❌ Failed to fetch user role: $e');
      }
    }

    if (!mounted) {
      debugPrint('[REALTIME] ⚠️ Widget not mounted, skipping message');
      return;
    }

    // Show notification for message from another user
    unawaited(
      NotificationService.showMessageNotification(
        incomingMessage['sender_name'] ?? 'User',
        incomingMessage['content'] ?? '',
      ),
    );

    // Check if message already exists by server ID to avoid duplicates
    final messageExists = _messages.any(
      (msg) => msg['id'] == incomingMessage['id'],
    );

    debugPrint(
      '[REALTIME] 🔍 Message exists: $messageExists, ID: ${incomingMessage['id']}',
    );

    if (!messageExists) {
      debugPrint(
        '[REALTIME] ✅ Adding new message to UI with complete data from trigger',
      );
      debugPrint(
        '[REALTIME] � sender_name=${incomingMessage['sender_name']}, '
        'prev_sender_id=${incomingMessage['prev_sender_id']}, '
        'next_sender_id=${incomingMessage['next_sender_id']}',
      );

      // Get the previous message ID before inserting (for updating its next_sender_id)
      final previousMessageId = _messages.isNotEmpty
          ? _messages[0]['id'] ?? _messages[0]['clientId']
          : null;

      // Queue styling update for the previous message (its next_sender_id will change)
      if (previousMessageId != null) {
        _realtimeUpdateQueue.add({
          'id': previousMessageId,
          'data': {'next_sender_id': incomingMessage['sender_id']},
        });
      }

      // Queue styling update for the last queue message if it exists
      if (_queueMessages.isNotEmpty) {
        final lastQueueMessageId =
            _queueMessages[_queueMessages.length - 1]['id'] ??
            _queueMessages[_queueMessages.length - 1]['clientId'];
        _realtimeUpdateQueue.add({
          'id': lastQueueMessageId,
          'data': {'next_sender_id': incomingMessage['sender_id']},
        });
      }

      // Use MessagesList's addNewMessage to trigger proper list rebuild
      // This only rebuilds MessagesList, NOT ChatPage
      _messagesListKey.currentState?.addNewMessage(incomingMessage);
      _lastAnimatedMessageId = incomingMessage['id'];

      if (mounted) {
        // Start processing queued styling updates
        _processRealtimeUpdates();

        // Clear animation ID after animation completes (no setState needed - just clear variable)
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) {
            _lastAnimatedMessageId = null;
          }
        });

        // Database trigger already calculated sender_name, prev_sender_id, next_sender_id
        // Realtime includes them, so no refresh needed ✅
      }
    }
  }

  /// Process realtime styling updates sequentially to avoid corruption
  Future<void> _processRealtimeUpdates() async {
    if (_isProcessingRealtimeUpdates || _realtimeUpdateQueue.isEmpty) {
      return;
    }

    _isProcessingRealtimeUpdates = true;

    while (_realtimeUpdateQueue.isNotEmpty) {
      if (!mounted) break;

      final update = _realtimeUpdateQueue.removeAt(0);
      final messageId = update['id'];
      final updateData = update['data'];

      debugPrint('[REALTIME] Processing styling update for message $messageId');

      // Update the message data directly (NO setState - only this message updates)
      final idx = _messages.indexWhere((msg) => msg['id'] == messageId);
      if (idx >= 0) {
        // Update data without setState
        _messages[idx] = {..._messages[idx], ...updateData};

        // Trigger rebuild ONLY for this specific message
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _messagesListKey.currentState?.updateMessageById(messageId);

            // Also rebuild adjacent message if needed
            if (idx + 1 < _messages.length) {
              final adjacentId =
                  _messages[idx + 1]['id'] ?? _messages[idx + 1]['clientId'];
              _messagesListKey.currentState?.updateMessageById(adjacentId);
            }
          }
        });
      }

      // Small delay to ensure UI updates before next message
      await Future.delayed(const Duration(milliseconds: 10));
    }

    _isProcessingRealtimeUpdates = false;
  }

  @override
  void dispose() {
    controller.dispose();
    _messagesScrollController.dispose();
    _badgeAnimController.dispose();
    _autoRetryTimer?.cancel();

    // Unsubscribe from Supabase Realtime channel
    if (_messagesChannel != null) {
      SupabaseService.unsubscribeFromMessages(_messagesChannel!);
    }

    super.dispose();
  }

  void _onMessagesScroll() {
    if (!_isLoadingMoreMessages &&
        _hasMoreMessages &&
        _messagesScrollController.position.pixels >=
            _messagesScrollController.position.maxScrollExtent - 200) {
      loadMessages(isLoadingMore: true);
    }
  }

  Future<void> loadMessages({bool isLoadingMore = false}) async {
    if (_isLoadingMoreMessages) return;

    setState(() {
      _isLoadingMoreMessages = true;
    });

    try {
      final page = isLoadingMore ? _messagesPage : 0;
      final response = await SupabaseService.getMessages(page);

      final newMessages = (response['messages'] as List)
          .cast<Map<String, dynamic>>()
          .map((msg) {
            // Ensure all loaded messages have required fields
            msg['status'] ??= 'Sent';
            msg['clientId'] ??=
                'server_${msg['id'] ?? DateTime.now().millisecondsSinceEpoch}';
            return msg;
          })
          .toList();

      setState(() {
        if (!isLoadingMore) {
          _messages.clear();
          _messagesPage = 0;
        }
        // Append old messages to the end of the list (visual top due to reverse: true)
        _messages.addAll(newMessages);
        _hasMoreMessages = response['hasMore'] ?? false;
        _isLoadingMoreMessages = false;
        if (_hasMoreMessages) {
          _messagesPage++;
        }
      });

      // After initial load, ensure messages are displayed
      if (!isLoadingMore && newMessages.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // Messages have been loaded and should now display
          if (mounted) {
            debugPrint('Initial messages loaded: ${_messages.length}');
          }
        });
      }

      // Cancel auto-retry if we successfully loaded messages
      if (!isLoadingMore) {
        _stopAutoRetry();
      }
    } catch (e) {
      debugPrint('Error loading messages: $e');
      setState(() {
        _isLoadingMoreMessages = false;
      });

      // Start auto-retry only on initial load failures (not when loading more)
      if (!isLoadingMore && _messages.isEmpty) {
        _startAutoRetry();
      }
    }
  }

  /// Starts automatic retry mechanism for message loading
  /// Checks every 10 seconds infinitely until messages load successfully
  void _startAutoRetry() {
    if (_isAutoRetryActive) return;

    _isAutoRetryActive = true;
    debugPrint('Auto-retry started: checking every 10 seconds...');

    _autoRetryTimer = Timer.periodic(_autoRetryInterval, (timer) {
      debugPrint('Auto-retry attempt...');

      // Attempt to load messages
      loadMessages().catchError((_) {
        // Continue retrying indefinitely on error
        debugPrint('Auto-retry will continue in 10 seconds...');
      });
    });
  }

  /// Stops the auto-retry mechanism
  void _stopAutoRetry() {
    if (_autoRetryTimer != null) {
      _autoRetryTimer?.cancel();
      _autoRetryTimer = null;
      _isAutoRetryActive = false;
      debugPrint('Auto-retry stopped');
    }
  }

  Future<void> checkMessageAccess() async {
    // For admins, always allow. For users, check if they have access
    if (widget.userRole == 'admin') {
      setState(() {
        _canSendMessages = true;
        _accessCheckComplete = true;
      });
      return;
    }

    try {
      // Check user's current status and message access
      final data = await SupabaseService.getUserStatus(
        widget.userId.toString(),
      );
      final status = data['status'] as String?;
      final canSendMessages = data['canSendMessages'];
      // Handle both boolean and integer (0/1) values from database
      final canSend = canSendMessages is bool
          ? canSendMessages
          : (canSendMessages is int ? canSendMessages == 1 : false);
      setState(() {
        _canSendMessages = status == 'verified' && canSend;
        _accessCheckComplete = true;
      });
    } catch (e) {
      debugPrint('Error checking message access: $e');
      setState(() {
        _canSendMessages = false;
        _accessCheckComplete = true;
      });
    }
  }

  /// Fetch pending requests count for admins
  Future<void> _fetchPendingRequestsCount() async {
    debugPrint(
      '[PENDING_REQUESTS] ════════════════════════════════════════════',
    );
    debugPrint('[PENDING_REQUESTS] 🔍 Starting to fetch pending requests...');
    debugPrint(
      '[PENDING_REQUESTS] User: ${widget.userName} | Role: ${widget.userRole}',
    );
    debugPrint('[PENDING_REQUESTS] Widget mounted: $mounted');

    try {
      // First, run diagnostic to see what statuses exist in database
      debugPrint(
        '[PENDING_REQUESTS] ▶️ STEP 1: Running diagnostic to check user statuses...',
      );
      final diagnostic = await SupabaseService.getAllUserStatuses();
      final totalUsers = diagnostic['totalUsers'] ?? 0;
      final statusDist = diagnostic['statusDistribution'] ?? {};

      debugPrint(
        '[PENDING_REQUESTS] ✅ Diagnostic complete: $totalUsers total users',
      );
      debugPrint('[PENDING_REQUESTS] 📊 Status distribution: $statusDist');

      debugPrint(
        '[PENDING_REQUESTS] ▶️ STEP 2: Fetching pending requests via getRequestsByStatus...',
      );
      final response = await SupabaseService.getRequestsByStatus('pending', 0);

      debugPrint('[PENDING_REQUESTS] ✅ getRequestsByStatus complete');
      debugPrint(
        '[PENDING_REQUESTS] 📥 Response keys: ${response.keys.toList()}',
      );

      final requestsList = response['requests'] as List? ?? [];
      final total = response['total'] ?? 0;
      final hasMore = response['hasMore'] ?? false;

      debugPrint('[PENDING_REQUESTS] 📊 Response details:');
      debugPrint(
        '[PENDING_REQUESTS]    - requests.length: ${requestsList.length}',
      );
      debugPrint('[PENDING_REQUESTS]    - total (count): $total');
      debugPrint('[PENDING_REQUESTS]    - hasMore: $hasMore');

      if (requestsList.isNotEmpty) {
        debugPrint('[PENDING_REQUESTS] 📄 First record:');
        final first = requestsList[0];
        debugPrint('[PENDING_REQUESTS]    - keys: ${first.keys.toList()}');
        debugPrint('[PENDING_REQUESTS]    - id: ${first['id']}');
        debugPrint('[PENDING_REQUESTS]    - name: ${first['name']}');
      }

      debugPrint('[PENDING_REQUESTS] ▶️ STEP 3: Updating UI state...');
      if (mounted) {
        debugPrint('[PENDING_REQUESTS] ✅ Widget is mounted');
        setState(() {
          _pendingRequestsCount = total;
          debugPrint(
            '[PENDING_REQUESTS] ✅ _pendingRequestsCount updated to: $_pendingRequestsCount',
          );
        });
      } else {
        debugPrint(
          '[PENDING_REQUESTS] ⚠️ Widget not mounted, skipping setState',
        );
      }
      debugPrint('[PENDING_REQUESTS] ✅ Fetch completed successfully');
      debugPrint(
        '[PENDING_REQUESTS] ════════════════════════════════════════════',
      );
    } catch (e) {
      debugPrint(
        '[PENDING_REQUESTS] ════════════════════════════════════════════',
      );
      debugPrint('[PENDING_REQUESTS] ❌ ERROR: $e');
      debugPrint('[PENDING_REQUESTS] Error type: ${e.runtimeType}');
      if (e is Exception) {
        debugPrint('[PENDING_REQUESTS] Exception message: ${e.toString()}');
      }
      debugPrint('[PENDING_REQUESTS] 🔺 Stack trace: ${StackTrace.current}');
      debugPrint(
        '[PENDING_REQUESTS] ════════════════════════════════════════════',
      );
    }
  }

  Future<void> verify(int id) async {
    final token = await Auth.getToken();
    if (token == null) throw Exception('No authentication token');
    await SupabaseService.verifyUser(userId: id.toString(), token: token);
  }

  Future<void> reject(int id) async {
    final token = await Auth.getToken();
    if (token == null) throw Exception('No authentication token');
    await SupabaseService.rejectUser(userId: id.toString(), token: token);
  }

  Future<void> updateRequest(int id, Map<String, dynamic> updates) async {
    try {
      await SupabaseService.updateRequest(
        userId: id.toString(),
        updates: updates,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> showEditDialog(Map<String, dynamic> request) async {
    String selectedStatus = request['status'] ?? 'pending';

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Request Status'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedStatus,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                items: ['pending', 'verified', 'rejected']
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(status.toUpperCase()),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    selectedStatus = value;
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () {
              if (selectedStatus != request['status']) {
                updateRequest(request['id'], {'status': selectedStatus});
              }
              Navigator.pop(context);
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  /// ============================================================================
  /// MESSAGE SYNCHRONIZATION AND STATUS MANAGEMENT
  /// ============================================================================

  /// END MESSAGE SYNCHRONIZATION
  /// ============================================================================

  /// Add message to queue instead of sending immediately
  void sendMessage() {
    final text = controller.text.trim();
    if (text.isEmpty) return;

    debugPrint('[QUEUE] 📝 User typed message: "$text"');

    // Check if user has permission to send messages
    if (!_canSendMessages && widget.userRole != 'admin') {
      debugPrint('[QUEUE] ❌ User does not have permission to send messages');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to send messages.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    controller.clear();

    // Create display message for queue
    final now = DateTime.now();
    final queueDisplayClientId =
        'queue_${now.millisecondsSinceEpoch}_${now.microsecond}';
    final queueDisplayMessage = {
      'id': queueDisplayClientId,
      'clientId': queueDisplayClientId,
      'sender_id': widget.userId,
      'sender_name': widget.userName,
      'content': text,
      'role': widget.userRole,
      'created_at': now.toIso8601String(),
      'status': 'Queued',
    };

    // Add to display queue immediately (shows with loading)
    setState(() {
      _queueMessages.insert(0, queueDisplayMessage);
      debugPrint(
        '[QUEUE] ✅ Added to display queue. Display queue size: ${_queueMessages.length}',
      );
    });

    // Trigger animation for the new message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final messagesListState = _messagesListKey.currentState;
      if (messagesListState != null) {
        messagesListState.animateMessage(queueDisplayClientId);
      }
    });

    // Add message to processing queue
    _messageQueue.add({
      'content': text,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'displayClientId': queueDisplayClientId,
    });

    debugPrint(
      '[QUEUE] ✅ Message added to processing queue. Queue size: ${_messageQueue.length}',
    );

    // Start processing queue if not already processing
    _processMessageQueue();
  }

  /// Process messages from queue sequentially
  Future<void> _processMessageQueue() async {
    if (_isProcessingQueue) {
      debugPrint('[QUEUE] ⏳ Already processing queue, skipping');
      return;
    }

    if (_messageQueue.isEmpty) {
      debugPrint('[QUEUE] ✓ Queue is empty, processing complete');
      return;
    }

    _isProcessingQueue = true;

    while (_messageQueue.isNotEmpty) {
      final queuedMessage = _messageQueue.removeAt(0);
      final text = queuedMessage['content'] as String;
      final displayClientId = queuedMessage['displayClientId'] as String;

      debugPrint(
        '[QUEUE] 🔄 Processing message from queue. Remaining: ${_messageQueue.length}',
      );

      // ====================================================================
      // STEP 0: Message already added to queue display in sendMessage()
      // ====================================================================
      // Just update status to 'Sending' to show loading indicator
      if (mounted) {
        setState(() {
          final displayIndex = _queueMessages.indexWhere(
            (msg) => msg['clientId'] == displayClientId,
          );
          if (displayIndex >= 0) {
            _queueMessages[displayIndex]['status'] = 'Sending';
          }
        });
      }

      // Scroll to show the message
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_messagesScrollController.hasClients) {
          _messagesScrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });

      // ====================================================================
      // STEP 1: SEND TO SERVER
      // ====================================================================
      try {
        debugPrint('[SEND_MSG] 🚀 Sending message to server...');
        final response = await SupabaseService.sendMessage(
          senderId: widget.userId.toString(),
          content: text,
        );

        debugPrint('[SEND_MSG] 📥 Received response from server');

        final sentMessageData = response['data'] as Map<String, dynamic>;
        final realMessageId = sentMessageData['id'];

        // Remove from queue once confirmed, add to confirmed messages
        if (mounted) {
          setState(() {
            // Find queued message by displayClientId and remove from queue
            final queueIndex = _queueMessages.indexWhere(
              (msg) => msg['clientId'] == displayClientId,
            );

            if (queueIndex >= 0) {
              _queueMessages.removeAt(queueIndex);
              debugPrint(
                '[SEND_MSG] ✓ Removed from queue (was loading). Real ID: $realMessageId',
              );
            }

            // Add confirmed message to confirmed messages list (at index 0)
            final realMessage = {
              ...sentMessageData,
              'status': 'Sent',
              'clientId': null,
              'sender_name': widget.userName,
            };

            // Update previous message's next_sender_id if there are messages
            if (_messages.isNotEmpty) {
              _messages[0]['next_sender_id'] = sentMessageData['sender_id'];
            }

            _messages.insert(0, realMessage);
            
            // FIX DOUBLE ANIMATION:
            // Do NOT set _lastAnimatedMessageId here, because that triggers a NEW animation.
            // Instead, mark this message as "already animated" so it stays visible without re-animating.
            _messagesListKey.currentState?.markMessagesAsAnimated([realMessageId]);
            
            debugPrint(
              '[SEND_MSG] ✅ Message confirmed and moved to messages list. Queue pending: ${_messageQueue.length}',
            );
          });
        }
      } catch (e) {
        debugPrint('[SEND_MSG] ❌ ERROR: $e');

        if (mounted) {
          setState(() {
            // Find message by displayClientId and mark as failed
            final failedIndex = _queueMessages.indexWhere(
              (msg) => msg['clientId'] == displayClientId,
            );
            if (failedIndex >= 0) {
              _queueMessages[failedIndex]['status'] = 'Failed';
              debugPrint(
                '[SEND_MSG] 🔴 Queue message at index $failedIndex marked as Failed',
              );
            }
          });
        }
      }

      // No delay - continue immediately with next message
    }

    _isProcessingQueue = false;
    debugPrint('[QUEUE] ✓ Queue processing complete');
  }

  /// Resend a failed message - add back to queue
  Future<void> _resendMessage(String content) async {
    debugPrint('[RESEND] 🔄 Retrying message: $content');

    // Find the failed message in queue messages
    final failedIndex = _queueMessages.indexWhere(
      (msg) =>
          msg['content'] == content &&
          msg['sender_id'] == widget.userId &&
          msg['status'] == 'Failed',
    );

    if (failedIndex < 0) {
      debugPrint('[RESEND] ❌ Failed message not found in queue');
      return;
    }

    // Get the failed message's ID (for re-linking)
    final failedMessageId =
        _queueMessages[failedIndex]['id'] ??
        _queueMessages[failedIndex]['clientId'];

    // Update status to 'Queued' instead of removing (keep it in display)
    setState(() {
      _queueMessages[failedIndex]['status'] = 'Queued';
      debugPrint('[RESEND] ✅ Updated failed message status to Queued');
    });

    // Add back to processing queue WITH the display client ID
    _messageQueue.add({
      'content': content,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'displayClientId': failedMessageId,
    });

    debugPrint(
      '[RESEND] ✅ Message re-queued. Queue size: ${_messageQueue.length}',
    );

    // Start processing queue
    _processMessageQueue();
  }

  Widget _buildMessagesTab() {
    return Column(
      children: [
        Expanded(
          child: MessagesList(
            key: _messagesListKey,
            messages: messages,
            queueMessages: _queueMessages,
            scrollController: _messagesScrollController,
            userId: widget.userId,
            lastAnimatedMessageId: _lastAnimatedMessageId,
            isLoadingMore: _isLoadingMoreMessages,
            onResendMessage: _resendMessage,
          ),
        ),
        if (widget.userRole == 'admin' ||
            !_accessCheckComplete ||
            _canSendMessages)
          MessageInput(
            controller: controller,
            onSend: sendMessage,
            enabled: _canSendMessages || widget.userRole == 'admin',
          )
        else
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 32, color: Config.textHint),
                  const SizedBox(height: 8),
                  Text(
                    'You do not have permission to send messages',
                    style: TextStyle(color: Config.textTertiary, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'Contact an administrator to request access',
                    style: TextStyle(color: Config.textHint, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      '[CHAT_PAGE_BUILD] 🏗️ Building ChatPage - userRole: ${widget.userRole}, _pendingRequestsCount: $_pendingRequestsCount',
    );

    return Scaffold(
      backgroundColor: Config.background,
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        toolbarHeight: 56,
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Chat',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Config.textPrimary,
            ),
          ),
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Config.primaryColor,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        backgroundColor: Config.textTimestamp,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Stack(
              children: [
                Material(
                  color: Colors.transparent,
                  child: PopupMenuButton<String>(
                    offset: const Offset(0, 2),
                    position: PopupMenuPosition.under,
                    borderRadius: BorderRadius.circular(32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    color: Config.background,
                    elevation: 8,
                    shadowColor: const Color.fromARGB(95, 0, 0, 0),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      child: ProfileAvatar(fullName: widget.userName, size: 36),
                    ),
                    itemBuilder: (context) => <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        enabled: false,
                        padding: const EdgeInsets.only(
                          left: 12,
                          right: 12,
                          bottom: 6,
                        ),
                        height: 56,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2),
                              child: ProfileAvatar(
                                fullName: widget.userName,
                                size: 40,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    widget.userName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: Config.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    widget.userEmail,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w400,
                                      fontSize: 12,
                                      color: Config.textTertiary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuDivider(height: 1, color: Config.divider),
                      if (widget.userRole == 'admin') ...[
                        PopupMenuItem<String>(
                          value: 'requests',
                          height: 40,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.checklist,
                                color: Config.textSecondary,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Requests',
                                style: TextStyle(
                                  color: Config.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                              if (_pendingRequestsCount > 0) ...[
                                const SizedBox(width: 8),
                                Builder(
                                  builder: (context) {
                                    debugPrint(
                                      '[BADGE] 🎫 Rendering badge with count: $_pendingRequestsCount',
                                    );
                                    return Container(
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 0,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        shape: BoxShape.rectangle,
                                        color: Config.error,
                                      ),
                                      child: Center(
                                        child: Text(
                                          _pendingRequestsCount.toString(),
                                          style: TextStyle(
                                            color: Config.textLight,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ] else ...[
                                Builder(
                                  builder: (context) {
                                    debugPrint(
                                      '[BADGE] ❌ No badge - _pendingRequestsCount: $_pendingRequestsCount',
                                    );
                                    return const SizedBox.shrink();
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                        PopupMenuDivider(height: 1, color: Config.divider),
                      ],
                      PopupMenuItem<String>(
                        value: 'logout',
                        height: 40,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.logout, color: Config.error, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Logout',
                              style: TextStyle(
                                color: Config.error,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      if (value == 'requests') {
                        Navigator.pushNamed(context, '/requests');
                      } else if (value == 'logout') {
                        // Safely disconnect socket before logout
                        SocketService.safeDisconnect().then((_) {
                          // Clear stored login data
                          Auth.clearLogin().then((_) {
                            if (!mounted) return;
                            Navigator.pushReplacement(
                              // ignore: use_build_context_synchronously
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AuthPage(),
                              ),
                            );
                          });
                        });
                      }
                    },
                  ),
                ),
                // Badge outside PopupMenuButton - small circle indicator
                if (widget.userRole == 'admin' && _pendingRequestsCount > 0)
                  Builder(
                    builder: (context) {
                      debugPrint(
                        '[BADGE_CIRCLE] 🔴 Rendering circular badge with count: $_pendingRequestsCount',
                      );
                      return Positioned(
                        top: 2,
                        right: 2,
                        child: ScaleTransition(
                          scale: _badgeAnimController.drive(
                            TweenSequence<double>([
                              TweenSequenceItem<double>(
                                tween: Tween<double>(
                                  begin: 1.0,
                                  end: 0.7,
                                ).chain(CurveTween(curve: Curves.easeInOut)),
                                weight: 50,
                              ),
                              TweenSequenceItem<double>(
                                tween: Tween<double>(
                                  begin: 0.7,
                                  end: 1.0,
                                ).chain(CurveTween(curve: Curves.easeInOut)),
                                weight: 50,
                              ),
                            ]),
                          ),
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Config.error,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Config.textTimestamp,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
      body: _buildMessagesTab(),
    );
  }
}
