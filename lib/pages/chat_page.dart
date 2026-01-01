import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config.dart';
import '../services/firebase_service.dart';
import '../models/message.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/messages_list.dart';
import '../widgets/message_input.dart';
import 'auth_page.dart';
import 'requests_page.dart';
import '../services/notification_service.dart';
import '../services/theme_service.dart';
import 'dart:async';

// Internal Message class removed - using lib/models/message.dart instead

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
  final String userId;
  final String userName;
  final String userEmail;
  final String userRole;
  final bool canSendMessages;

  const ChatPage({
    super.key,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.userRole,
    this.canSendMessages = false,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final baseUrl = Config.baseUrl;

  // State
  final List<Map<String, dynamic>> _messageQueue = [];
  bool _isProcessingQueue = false;
  late bool _canSendMessages = widget.canSendMessages;
  bool _isInitialLoad = true;

  // Notifiers
  final ValueNotifier<List<Map<String, dynamic>>> _messagesNotifier =
      ValueNotifier([]);
  final ValueNotifier<List<Map<String, dynamic>>> _queueNotifier =
      ValueNotifier([]);

  // Getters for convenience
  List<Map<String, dynamic>> get _messages => _messagesNotifier.value;
  List<Map<String, dynamic>> get _queueMessages => _queueNotifier.value;

  // Controllers & Listeners
  final TextEditingController controller = TextEditingController();
  final ScrollController _messagesScrollController = ScrollController();
  final GlobalKey<MessagesListState> _messagesListKey = GlobalKey();
  late AnimationController _badgeAnimController;

  // Subscriptions
  // Subscriptions
  StreamSubscription? _messagesSubscription;
  StreamSubscription? _userDataSubscription;
  StreamSubscription? _requestsCountSubscription;

  int _pendingRequestsCount = 0;
  bool _isLoadingMoreMessages = false;

  // Pagination
  bool _hasMoreMessages = true;

  // Animation tracking
  String? _lastAnimatedMessageId;

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

    // Check message access or fetch admin counts
    if (widget.userRole != 'admin') {
      checkMessageAccess();
    } else {
      _listenToPendingRequestsCount();
      _badgeAnimController.repeat();
    }
  }

  void checkMessageAccess() {
    _userDataSubscription?.cancel();
    _userDataSubscription = FirebaseService.getUserDataStream(widget.userId).listen(
      (snapshot) {
        if (!mounted) return;
        final userData = snapshot.data();
        if (userData == null) return;

        final bool newAccess = userData['can_send_messages'] ?? false;
        // final String newStatus = userData['status'] ?? 'pending'; // Unused for now

        // Check for status changes to trigger notification
        // We could store previous status to compare, but for now we trust the stream update
        // implies a change or initial load. To avoid notification on initial load,
        // we could check a flag, but the requirement says "If a request status changes".
        // Real-time stream fires on first connect too.
        // We'll rely on the fact that if we are actively chatting, a change is notable.

        if (newAccess != _canSendMessages) {
          if (newAccess) {
            NotificationService.showMessageNotification(
              'System',
              'You can now send messages.',
            );
          }
        }

        setState(() {
          _canSendMessages = newAccess;
        });

        // Local Persistence: Automatically save value when updated
        FirebaseService.saveUserConfig(
          canSendMessages: newAccess,
          role: widget.userRole,
        );

        debugPrint(
          '[CHAT_PAGE] 🔄 Realtime status update - can_send_messages: $_canSendMessages',
        );
      },
      onError: (e) {
        debugPrint('[CHAT_PAGE] ❌ Error in user data stream: $e');
      },
    );
  }

  @override
  void dispose() {
    controller.dispose();
    _messagesScrollController.dispose();
    _messagesSubscription?.cancel();
    _userDataSubscription?.cancel();
    _requestsCountSubscription?.cancel();
    _badgeAnimController.dispose();
    super.dispose();
  }

  void _onMessagesScroll() {
    if (_messagesScrollController.hasClients) {
      final position = _messagesScrollController.position;
      // debugPrint('[SCROLL] Offset: ${position.pixels}, Max: ${position.maxScrollExtent}');

      if (!_isLoadingMoreMessages &&
          _hasMoreMessages &&
          position.pixels >= position.maxScrollExtent - 200) {
        debugPrint('[SCROLL] 📜 Triggering load more messages...');
        loadMessages(isLoadingMore: true);
      }
    }
  }

  void _listenToPendingRequestsCount() {
    _requestsCountSubscription?.cancel();
    _requestsCountSubscription = FirebaseService.getPendingRequestsCountStream()
        .listen((requestCount) {
          if (mounted) {
            setState(() {
              _pendingRequestsCount = requestCount;
            });
            debugPrint(
              '[CHAT_PAGE] 🔄 Realtime pending requests: $requestCount',
            );
          }
        });
  }

  void loadMessages({bool isLoadingMore = false}) {
    if (_isLoadingMoreMessages) return;

    if (isLoadingMore && !_hasMoreMessages) return;

    setState(() {
      _isLoadingMoreMessages = true;
    });

    if (isLoadingMore) {
      // Pagination logic: Load older messages
      if (_messages.isEmpty) {
        setState(() => _isLoadingMoreMessages = false);
        return;
      }

      final lastMessage = _messages.last;
      DateTime? lastTimestamp;
      if (lastMessage['created_at'] != null) {
        lastTimestamp = DateTime.parse(lastMessage['created_at']);
      } else {
        lastTimestamp = DateTime.now();
      }

      FirebaseService.getOldMessages(
            limit: 50,
            lastMessageTimestamp: lastTimestamp,
          )
          .then((oldMessagesRaw) {
            if (!mounted) return;

            if (oldMessagesRaw.isEmpty) {
              setState(() {
                _hasMoreMessages = false;
                _isLoadingMoreMessages = false;
              });
              return;
            }

            // Convert to ChatMessage and back to Map to ensure consistent format
            final oldMessagesConfirmed = oldMessagesRaw
                .map((m) => ChatMessage.fromMap(m).toMap())
                .toList();

            // Filter duplicates just in case
            final existingIds = _messages.map((m) => m['id']).toSet();
            final uniqueMessages = oldMessagesConfirmed
                .where((m) => !existingIds.contains(m['id']))
                .toList();

            if (uniqueMessages.isNotEmpty) {
              debugPrint(
                '[PAGINATION] 📜 Loaded ${uniqueMessages.length} older messages',
              );

              // Update UI and list logic via MessagesListState
              // This handles updating the Notifier value correctly
              _messagesListKey.currentState?.addOlderMessages(uniqueMessages);
            }

            setState(() {
              _isLoadingMoreMessages = false;
            });
          })
          .catchError((e) {
            debugPrint('[CHAT_PAGE] ❌ Error loading old messages: $e');
            if (mounted) {
              setState(() => _isLoadingMoreMessages = false);
            }
          });

      return;
    }

    _messagesSubscription?.cancel();

    // Use pagination with limit of 50 messages per page
    _messagesSubscription = FirebaseService.getMessagesStream(limit: 50).listen(
      (snapshot) {
        if (!mounted) return;

        final newMessages = snapshot.docs
            .map((doc) => ChatMessage.fromMap({...doc.data(), 'id': doc.id}))
            .toList();

        // Build a set of existing message IDs for quick lookup
        final existingIds = _messages.map((m) => m['id']).toSet();

        // Only add truly new messages (incremental update)
        final messagesToAdd = newMessages
            .where((msg) => !existingIds.contains(msg.id))
            .toList();

        if (_isInitialLoad) {
          // Initial Load: Set messages directly without animation
          setState(() {
            // Note: messagesToAdd is already sorted newest first (desc)
            // But we want to display them in the list. messagesNotifier handles the list.
            // MessagesList expects [Newest, ..., Oldest]
            _messagesNotifier.value = messagesToAdd
                .map((m) => m.toMap())
                .toList();
            _isInitialLoad = false;
          });

          // Mark as animated to prevent future animations
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _messagesListKey.currentState?.markMessagesAsAnimated(
              messagesToAdd.map((m) => m.id).toList(),
            );
          });

          debugPrint(
            '[FIRESTORE] ✅ Initial batch loaded: ${messagesToAdd.length}',
          );
        } else {
          // Incremental Update: Add all messages efficiently
          if (messagesToAdd.isNotEmpty) {
            debugPrint(
              '[FIRESTORE] 📥 Received ${messagesToAdd.length} new messages. Processing batch...',
            );

            // Trigger notification for background messages
            for (var msg in messagesToAdd) {
              if (msg.senderId != widget.userId) {
                NotificationService.showMessageNotification(
                  msg.senderName,
                  msg.content,
                );
              }
            }

            final messagesListState = _messagesListKey.currentState;

            // 1. Update Queue (Batch Removal)
            // Use Notifier update directly to avoid setState
            final currentQueue = List<Map<String, dynamic>>.from(
              _queueNotifier.value,
            );
            final initialQueueLength = currentQueue.length;

            debugPrint(
              '[QUEUE] Current Queue IDs: ${currentQueue.map((m) => m['id']).toList()}',
            );

            // Collect IDs to remove
            final idsToRemove = messagesToAdd.map((m) => m.id).toSet();

            currentQueue.removeWhere((queueMsg) {
              final match = idsToRemove.contains(queueMsg['id']);
              if (match) {
                debugPrint(
                  '[QUEUE] 🗑️ Removing queued message: ${queueMsg['id']}',
                );
              }
              return match;
            });

            if (currentQueue.length != initialQueueLength) {
              debugPrint(
                '[QUEUE] ✅ Removed ${initialQueueLength - currentQueue.length} messages from queue',
              );
              _queueNotifier.value = currentQueue;
            } else {
              debugPrint(
                '[QUEUE] ⚠️ No messages removed from queue (IDs might not match). New IDs: $idsToRemove',
              );
            }

            // 2. Add New Messages (Batch Insertion)
            // We need to pass [Oldest -> Newest] to addNewMessages because it inserts
            // each item at index 0 sequentially.
            // messagesToAdd is [Newest -> Oldest] (Firestore DESC).
            // So we reverse it.
            final messagesToInsert = messagesToAdd.reversed
                .map((m) => m.toMap())
                .toList();

            messagesListState?.addNewMessages(messagesToInsert);
          }
        }

        // ONLY call setState if we were loading (to turn it off)
        if (mounted && _isLoadingMoreMessages) {
          setState(() {
            _isLoadingMoreMessages = false;
          });
        }
      },
      onError: (e) {
        debugPrint('[CHAT_PAGE] Error in messages stream: $e');
        if (mounted) {
          setState(() {
            _isLoadingMoreMessages = false;
          });
        }
      },
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

    // Generate a valid Firestore ID client-side
    // This allows us to match the queued message with the verified message
    // preventing double-rendering/flickering
    final docId = FirebaseService.generateMessageId();

    // Create display message for queue
    final now = DateTime.now();
    final queueDisplayMessage = {
      'id': docId, // Use the real ID immediately
      'clientId': docId,
      'sender_id': widget.userId,
      'sender_name': widget.userName,
      'content': text,
      'role': widget.userRole,
      'created_at': now.toIso8601String(),
      'status': 'Queued',
    };

    // Add to display queue immediately (shows with loading)
    // Use Notifier update instead of setState to avoid rebuilding ChatPage
    final currentQueue = List<Map<String, dynamic>>.from(_queueNotifier.value);
    currentQueue.insert(0, queueDisplayMessage);
    _queueNotifier.value = currentQueue;

    debugPrint(
      '[QUEUE] ✅ Added to display queue. Display queue size: ${currentQueue.length}',
    );

    // Trigger animation for the new message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final messagesListState = _messagesListKey.currentState;
      if (messagesListState != null) {
        messagesListState.animateMessage(docId);
      }
    });

    // Add message to processing queue
    _messageQueue.add({
      'content': text,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'displayClientId': docId, // Pass the real ID
      'docId': docId, // Pass explicitly
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
      final docId = queuedMessage['docId'] as String;

      debugPrint(
        '[QUEUE] 🔄 Processing message from queue. Remaining: ${_messageQueue.length}',
      );

      // ====================================================================
      // STEP 0: Message already added to queue display in sendMessage()
      // ====================================================================
      // Just update status to 'Sending' to show loading indicator
      if (mounted) {
        // Update via Notifier - NO setState
        final currentQueue = List<Map<String, dynamic>>.from(
          _queueNotifier.value,
        );
        final displayIndex = currentQueue.indexWhere(
          (msg) => msg['id'] == displayClientId,
        );
        if (displayIndex >= 0) {
          currentQueue[displayIndex]['status'] = 'Sending';
          _queueNotifier.value = currentQueue;
        }
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
      // STEP 1: SEND TO SERVER (Firestore)
      // ====================================================================
      try {
        debugPrint('[SEND_MSG] 🚀 Sending message to Firestore...');
        await FirebaseService.sendMessage(
          senderId: widget.userId,
          senderName: widget.userName,
          content: text,
          role: widget.userRole,
          docId: docId,
        );

        debugPrint('[SEND_MSG] 📥 Message sent to Firestore successfully');

        // Queue removal now happens automatically in the Firestore listener
        // when the message is detected in the snapshot
      } catch (e) {
        debugPrint('[SEND_MSG] ❌ ERROR: $e');

        if (mounted) {
          // Update via Notifier - NO setState
          final currentQueue = List<Map<String, dynamic>>.from(
            _queueNotifier.value,
          );
          final failedIndex = currentQueue.indexWhere(
            (msg) => msg['clientId'] == displayClientId,
          );
          if (failedIndex >= 0) {
            currentQueue[failedIndex]['status'] = 'Failed';
            _queueNotifier.value = currentQueue;
            debugPrint(
              '[SEND_MSG] 🔴 Queue message at index $failedIndex marked as Failed',
            );
          }
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

    // Get the failed message's info (for re-linking)
    // final failedMessageContent = _queueMessages[failedIndex]['content'];

    // Update status to 'Failed' (since we're not implementing retry here yet)
    // Use Notifier update - NO setState
    final currentQueue = List<Map<String, dynamic>>.from(_queueNotifier.value);
    if (failedIndex < currentQueue.length) {
      currentQueue[failedIndex]['status'] = 'Failed';
      _queueNotifier.value = currentQueue;
    }
  }

  Widget _buildMessagesTab() {
    return Column(
      children: [
        Expanded(
          child: MessagesList(
            key: _messagesListKey,
            messagesNotifier: _messagesNotifier,
            queueMessagesNotifier: _queueNotifier,
            scrollController: _messagesScrollController,
            userId: widget.userId,
            lastAnimatedMessageId: _lastAnimatedMessageId,
            isLoadingMore: _isLoadingMoreMessages,
            onResendMessage: _resendMessage,
          ),
        ),
        MessageInput(
          controller: controller,
          onSend: sendMessage,
          enabled: widget.userRole == 'admin' || _canSendMessages,
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
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        toolbarHeight: 56,
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Chat',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Config.getTextColor(context),
            ),
          ),
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Config.primaryColor,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        backgroundColor: Config.getSurfaceColor(context),
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Stack(
              children: [
                Material(
                  color: Colors.transparent,
                  child: PopupMenuButton<String>(
                    position: PopupMenuPosition.under,
                    borderRadius: BorderRadius.circular(32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    color: Config.isDarkMode(context)
                        ? Color.fromRGBO(38, 38, 38, 1)
                        : Color.fromRGBO(245, 245, 245, 1),
                    elevation: 2,
                    shadowColor: Config.getShadowColor(context),
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
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: Config.getTextColor(context),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    widget.userEmail,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w400,
                                      fontSize: 12,
                                      color: Config.getTextColor(
                                        context,
                                        level: 2,
                                      ),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuDivider(
                        height: 1,
                        color: Config.isDarkMode(context)
                            ? Color.fromRGBO(70, 70, 70, 1)
                            : Color.fromRGBO(229, 229, 229, 1),
                      ),
                      if (widget.userRole == 'admin') ...[
                        PopupMenuItem<String>(
                          value: 'requests',
                          height: 40,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.checklist,
                                color: Config.getTextColor(context, level: 2),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Requests',
                                style: TextStyle(
                                  color: Config.getTextColor(context, level: 2),
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
                                        horizontal: 6,
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
                        PopupMenuDivider(
                          height: 1,
                          color: Config.isDarkMode(context)
                              ? Color.fromRGBO(70, 70, 70, 1)
                              : Color.fromRGBO(229, 229, 229, 1),
                        ),
                      ],
                      // Theme Selection
                      PopupMenuItem<String>(
                        value: 'theme',
                        height: 40,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              ThemeService.themeMode.value == ThemeMode.dark
                                  ? Icons.dark_mode
                                  : ThemeService.themeMode.value ==
                                        ThemeMode.light
                                  ? Icons.light_mode
                                  : Icons.brightness_4_outlined,
                              color: Config.getTextColor(context, level: 2),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Theme: ${ThemeService.themeModeString}',
                              style: TextStyle(
                                color: Config.getTextColor(context, level: 2),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuDivider(
                        height: 1,
                        color: Config.isDarkMode(context)
                            ? Color.fromRGBO(70, 70, 70, 1)
                            : Color.fromRGBO(229, 229, 229, 1),
                      ),
                      PopupMenuItem<String>(
                        value: 'logout',
                        height: 40,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
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
                    onSelected: (value) async {
                      if (value == 'requests') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RequestsPage(),
                          ),
                        );
                      } else if (value == 'theme') {
                        // Cycle theme: System -> Light -> Dark -> System
                        ThemeMode next;
                        if (ThemeService.themeMode.value == ThemeMode.system) {
                          next = ThemeMode.light;
                        } else if (ThemeService.themeMode.value ==
                            ThemeMode.light) {
                          next = ThemeMode.dark;
                        } else {
                          next = ThemeMode.system;
                        }
                        await ThemeService.setTheme(next);
                      } else if (value == 'logout') {
                        try {
                          final navigator = Navigator.of(context);
                          await FirebaseService.logout();
                          if (!mounted) return;
                          navigator.pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const AuthPage()),
                            (route) => false,
                          );
                        } catch (e) {
                          debugPrint('[CHAT_PAGE] Error during logout: $e');
                        }
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
                                color: Config.getSurfaceColor(context),
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
