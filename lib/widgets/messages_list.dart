import 'package:flutter/material.dart';
import '../config.dart';
import 'message_item.dart';

class MessagesList extends StatefulWidget {
  final List<Map<String, dynamic>> messages; // Confirmed messages from Supabase
  final List<Map<String, dynamic>>
  queueMessages; // Messages being sent (shown as loading)
  final ScrollController scrollController;
  final int userId;
  final dynamic lastAnimatedMessageId;
  final bool isLoadingMore;
  final Function(String content)? onResendMessage;

  const MessagesList({
    required this.messages,
    required this.queueMessages,
    required this.scrollController,
    required this.userId,
    required this.lastAnimatedMessageId,
    this.isLoadingMore = false,
    this.onResendMessage,
    super.key,
  });

  @override
  State<MessagesList> createState() => MessagesListState();
}

class MessagesListState extends State<MessagesList>
    with TickerProviderStateMixin {
  // Track which message IDs need to be rebuilt using a notifier instead of setState
  final Set<dynamic> _messagesToRebuild = {};
  late ValueNotifier<Set<dynamic>> _rebuildNotifier;

  // Map of message IDs to their individual animation controllers
  // Each message gets its own controller so animations don't interfere
  final Map<dynamic, AnimationController> _messageControllers = {};

  // Track which messages have completed their animation
  final Set<dynamic> _completedAnimations = {};

  // Track the previously animated message to trigger old message animation
  dynamic _previouslyAnimatedMessageId;

  @override
  void initState() {
    super.initState();
    _rebuildNotifier = ValueNotifier<Set<dynamic>>({});
  }

  @override
  void didUpdateWidget(MessagesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When a new message arrives (lastAnimatedMessageId changes)
    if (widget.lastAnimatedMessageId != oldWidget.lastAnimatedMessageId &&
        widget.lastAnimatedMessageId != null) {
      // Trigger animation for new message
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerNewMessageAnimation(widget.lastAnimatedMessageId);
        // Trigger old message animation for the previously newest message
        if (_previouslyAnimatedMessageId != null) {
          _triggerOldMessageAnimation(_previouslyAnimatedMessageId);
        }
        _previouslyAnimatedMessageId = widget.lastAnimatedMessageId;
      });
    }
  }

  /// Formats a message time to HH:mm format
  String formatMessageTime(DateTime time) {
    return '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }

  /// Formats a date to show year, month, and day
  String formatMessageDate(DateTime date) {
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  /// Checks if two messages are from different days (based on server time)
  bool isDifferentDay(DateTime time1, DateTime time2) {
    return time1.year != time2.year ||
        time1.month != time2.month ||
        time1.day != time2.day;
  }

  /// Extracts message creation time from a message map
  DateTime getMessageTime(Map<String, dynamic> message) {
    return message['created_at'] != null
        ? DateTime.parse(message['created_at']).toLocal()
        : DateTime.now();
  }

  void _triggerNewMessageAnimation(dynamic messageId) {
    final controller = _getOrCreateController(messageId);
    controller.reset();
    controller.forward();
  }

  void _triggerOldMessageAnimation(dynamic messageId) {
    // Trigger rebuild for the previously newest message so it gets style update
    updateMessageById(messageId);
  }

  /// Get or create an AnimationController for a specific message
  AnimationController _getOrCreateController(dynamic messageId) {
    if (!_messageControllers.containsKey(messageId)) {
      _messageControllers[messageId] = AnimationController(
        duration: const Duration(milliseconds: 200),
        vsync: this,
      );
    }
    return _messageControllers[messageId]!;
  }

  /// Trigger animation for a specific message
  /// Does NOT call setState - uses ValueNotifier for targeted rebuild
  void animateMessage(dynamic messageId) {
    final controller = _getOrCreateController(messageId);
    controller.reset();
    _completedAnimations.remove(messageId);
    controller.forward();

    // Mark animation as completed after duration WITHOUT setState
    // Just add to set - ValueListenableBuilder in message builder will detect it
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _completedAnimations.add(messageId);
        // Notify that this message should rebuild (animation complete)
        _rebuildNotifier.value = Set.from([messageId]);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _rebuildNotifier.value = {};
        });
      }
    });
  }

  /// Mark messages as already animated so they display immediately without animation
  /// Used for initial batch of loaded messages that should be visible right away
  /// Does NOT trigger setState - just marks internally to avoid double rendering
  void markMessagesAsAnimated(List<dynamic> messageIds) {
    if (messageIds.isEmpty) return;

    for (var messageId in messageIds) {
      // Ensure controller exists
      _getOrCreateController(messageId);
      // Mark as completed so shouldAnimate will be false
      _completedAnimations.add(messageId);
    }
  }

  @override
  void dispose() {
    // Dispose all animation controllers
    for (var controller in _messageControllers.values) {
      controller.dispose();
    }
    _messageControllers.clear();
    _rebuildNotifier.dispose();
    super.dispose();
  }

  /// Public function to update a specific message by ID
  /// This will only rebuild that specific message, not the entire list
  void updateMessageById(dynamic messageId) {
    _messagesToRebuild.add(messageId);
    // Notify listeners without rebuilding the entire list
    _rebuildNotifier.value = Set.from(_messagesToRebuild);

    // Auto-clear after rebuild
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _messagesToRebuild.remove(messageId);
      _rebuildNotifier.value = Set.from(_messagesToRebuild);
    });
  }

  /// Add a new message directly to the list and animate it
  /// Used by ChatPage when a new realtime message arrives
  /// This only rebuilds MessagesList, not the entire ChatPage
  void addNewMessage(Map<String, dynamic> message) {
    final messageId = message['id'] ?? message['clientId'];

    // IMPORTANT: Start animation BEFORE setState so it's already running when build happens
    // This ensures SizeTransition has a non-zero value on first render
    _completedAnimations.remove(messageId);
    final controller = _getOrCreateController(messageId);
    controller.reset();
    controller.forward();

    // Mark animation as completed after duration
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _completedAnimations.add(messageId);
        // Notify that this message should rebuild (animation complete)
        _rebuildNotifier.value = Set.from([messageId]);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _rebuildNotifier.value = {};
        });
      }
    });

    // Insert at the top and trigger list rebuild (only MessagesListState rebuilds)
    setState(() {
      widget.messages.insert(0, message);
    });

    // Scroll to top immediately to show new message
    if (widget.scrollController.hasClients) {
      widget.scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// Clear all rebuild flags
  void clearRebuildFlags() {
    _messagesToRebuild.clear();
    _rebuildNotifier.value = {};
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.messages; // Confirmed messages
    final queueMessages = widget.queueMessages; // Queue messages (loading)
    final scrollController = widget.scrollController;
    final userId = widget.userId;
    final isLoadingMore = widget.isLoadingMore;

    // Combine ALL queue messages + ALL confirmed messages
    final allMessagesToDisplay = [...queueMessages, ...messages];

    if (allMessagesToDisplay.isNotEmpty) {
       debugPrint('[MESSAGES LIST] Building list with ${allMessagesToDisplay.length} messages');
       for (int k = 0; k < 3 && k < allMessagesToDisplay.length; k++) {
         debugPrint('[MESSAGES LIST] Item $k: ${allMessagesToDisplay[k]['content']} (ID: ${allMessagesToDisplay[k]['id']})');
       }
    }

    // Show loading indicator if no messages
    if (allMessagesToDisplay.isEmpty) {
      return Center(
        child: CircularProgressIndicator(
          color: Config.primaryColor,
          strokeWidth: 3,
        ),
      );
    }

    return RawScrollbar(
      controller: scrollController,
      thumbVisibility: true,
      trackVisibility: false,
      thickness: 6,
      radius: const Radius.circular(3),
      thumbColor: Config.primaryColor.withAlpha(100),
      interactive: true,
      child: ListView.builder(
        controller: scrollController,
        padding: EdgeInsets.only(right: 6),
        clipBehavior: Clip.none,
        itemCount: allMessagesToDisplay.length + (isLoadingMore ? 1 : 0) + 1,
        reverse: true,
        itemBuilder: (context, i) {
          // Show SizedBox at the very bottom (oldest message position, last index in reversed list)
          // This provides space for shadows to render without being clipped
          if (i == 0) {
            return Container(height: 12);
          }

          // Adjust index for actual messages
          final messageIndex = i - 1;

          // Show loading indicator at the top (end of reversed list)
          if (isLoadingMore && messageIndex == allMessagesToDisplay.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(
                  color: Config.primaryColor,
                  strokeWidth: 2,
                ),
              ),
            );
          }
          final message = allMessagesToDisplay[messageIndex];
          final messageId = message['id'] ?? message['clientId'];
          final time = getMessageTime(message);
          final isCurrentUser = message['sender_id'] == userId;
          final isInQueue = messageIndex < queueMessages.length;
          final messageOpacity = isInQueue ? 0.6 : 1.0;

          debugPrint(
            '[MESSAGES LIST] Rendering message ID: $messageId '
            '(Index: $messageIndex, Message Content: "${message['content']}", Message Role: ${message['role']}',
          );

          // Watch the rebuild notifier to check if this specific message needs rebuilding
          return ValueListenableBuilder<Set<dynamic>>(
            valueListenable: _rebuildNotifier,
            builder: (context, rebuildSet, child) {
              final shouldRebuild = rebuildSet.contains(messageId);

              // Animate ONLY if it's in the queue (sending) OR it's the specific new message added by ChatPage
              final shouldAnimate =
                  (isInQueue || messageId == widget.lastAnimatedMessageId) &&
                  !_completedAnimations.contains(messageId);

              // Get this message's individual animation controller
              final messageController = _getOrCreateController(messageId);

              final currentSenderId = message['sender_id'];
              final prevSenderId = message['prev_sender_id'];
              final nextSenderId = message['next_sender_id'];

              // For queue messages, calculate sender change based on adjacent messages in combined list
              var senderChangeFromPrev = false;
              var senderChangeToNext = false;

              if (isInQueue) {
                // Check if sender changed from previous message in combined list
                if (messageIndex > 0) {
                  final prevMessage = allMessagesToDisplay[messageIndex - 1];
                  senderChangeFromPrev =
                      prevMessage['sender_id'] != currentSenderId;
                } else {
                  senderChangeFromPrev = true;
                }

                // Check if sender changes to next message in combined list
                if (messageIndex + 1 < allMessagesToDisplay.length) {
                  final nextMessage = allMessagesToDisplay[messageIndex + 1];
                  senderChangeToNext =
                      nextMessage['sender_id'] != currentSenderId;
                } else {
                  senderChangeToNext = true;
                }
              } else {
                // For confirmed messages, use trigger data
                senderChangeFromPrev =
                    prevSenderId == null || currentSenderId != prevSenderId;
                senderChangeToNext =
                    nextSenderId == null || currentSenderId != nextSenderId;
              }

              // Check if this message is from a different day than the next message
              bool isDifferentDayFromNext = false;
              if (messageIndex + 1 < allMessagesToDisplay.length) {
                final nextMessageTime = getMessageTime(
                  allMessagesToDisplay[messageIndex + 1],
                );
                isDifferentDayFromNext = isDifferentDay(time, nextMessageTime);
              } else {
                // If this is the oldest message (last in reversed list), always show separator
                isDifferentDayFromNext = true;
              }

              // Check if this message is from a different day than the previous message
              DateTime? prevMessageTime;
              bool isDifferentDayFromPrev = false;
              if (messageIndex - 1 >= 0) {
                prevMessageTime = getMessageTime(
                  allMessagesToDisplay[messageIndex - 1],
                );
                isDifferentDayFromPrev = isDifferentDay(time, prevMessageTime);
              } else {
                // First message in the list (newest overall) is always in a new day
                isDifferentDayFromPrev = true;
              }

              // isNewestInDay: This is the newest (first shown) message in its day
              // This happens when the previous message (in list) is from a different day
              final isNewestInDay = isDifferentDayFromPrev;

              // For the oldest message in each day, show full styles
              final isOldestInDay = isDifferentDayFromNext;

              // Different styling logic for queue vs confirmed messages
              final shouldShowStyles = isInQueue
                  ? (senderChangeToNext ||
                        isOldestInDay) // Queue: show styles at END of group
                  : (senderChangeFromPrev ||
                        isOldestInDay); // Confirmed: show styles at START of group

              // Wrap messageWidget with key - use ValueKey to preserve state
              final keyedMessageWidget = KeyedSubtree(
                key: ValueKey(messageId),
                child: Opacity(
                  opacity: messageOpacity,
                  child: MessageItem(
                    message: message,
                    userId: userId,
                    shouldShowStyles: shouldShowStyles,
                    isOldestInDay: isOldestInDay,
                    isNewestInDay: isNewestInDay,
                    senderChangeToNext: senderChangeToNext,
                    isDifferentDayFromNext: isDifferentDayFromNext,
                    onResend: widget.onResendMessage != null
                        ? () => widget.onResendMessage!(
                            message['content'] as String,
                          )
                        : null,
                  ),
                ),
              );

              // NEW MESSAGE: Wrap with SizeTransition (expansion) + Slide + Fade
              // LOADED MESSAGE: Render at full size
              final animatedChild = shouldAnimate
                  ? SizeTransition(
                      sizeFactor: Tween<double>(begin: 0, end: 1).animate(
                        CurvedAnimation(
                          parent: messageController,
                          curve: Curves.easeOut,
                        ),
                      ),
                      child: SlideTransition(
                        position:
                            Tween<Offset>(
                              begin: isCurrentUser
                                  ? Offset(1.2, 0)
                                  : Offset(-1.2, 0),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: messageController,
                                curve: Curves.easeOut,
                              ),
                            ),
                        child: FadeTransition(
                          opacity: Tween<double>(begin: 0, end: 1).animate(
                            CurvedAnimation(
                              parent: messageController,
                              curve: Curves.easeOut,
                            ),
                          ),
                          child: keyedMessageWidget,
                        ),
                      ),
                    )
                  : keyedMessageWidget;


              // Apply expansion animation for new messages only
              final finalChild = animatedChild;

              // Wrap in RepaintBoundary ONLY for old messages that don't need rebuild
              // New messages and explicitly flagged messages rebuild normally
              return (shouldAnimate || shouldRebuild)
                  ? finalChild
                  : RepaintBoundary(child: finalChild);
            },
          );
        },
      ),
    );
  }
}
