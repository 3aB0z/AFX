import 'package:flutter/material.dart';
import '../config.dart';
import 'message_item.dart';

class MessagesList extends StatefulWidget {
  final ValueNotifier<List<Map<String, dynamic>>> messagesNotifier;
  final ValueNotifier<List<Map<String, dynamic>>> queueMessagesNotifier;
  final ScrollController scrollController;
  final String userId;
  final dynamic lastAnimatedMessageId;
  final bool isLoadingMore;
  final Function(String content)? onResendMessage;

  const MessagesList({
    required this.messagesNotifier,
    required this.queueMessagesNotifier,
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
        _rebuildNotifier.value = {messageId};
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
    addNewMessages([message]);
  }

  /// Add multiple new messages efficiently
  void addNewMessages(List<Map<String, dynamic>> newMessages) {
    if (newMessages.isEmpty) return;

    final currentMessages = List<Map<String, dynamic>>.from(
      widget.messagesNotifier.value,
    );

    // Process all messages: setup animation and insert
    // Iterate in reverse to maintain order (if list is [Oldest -> Newest], insert Newest first)
    // Actually newMessages usually comes sorted. We want to insert at index 0.
    // If input is [OldestNewMsg, ..., NewestNewMsg], we should insert Oldest first at 0, then Newer at 0...
    // Wait, if we insert at 0, we push others down.
    // If input is [Msg1, Msg2] (Msg2 is newer), and we want [Msg2, Msg1, OldMsgs...]
    // We should insert Msg1 at 0 -> [Msg1, Old...]
    // Then Msg2 at 0 -> [Msg2, Msg1, Old...]
    // So we iterate forward: 0..N? No.
    // ChatPage passes [Newest, ..., Oldest] in `messagesToAdd` if sorted by DESC.
    // Let's assume input order matters.

    for (var message in newMessages) {
      final messageId = message['id'] ?? message['clientId'];
      final isMe = message['sender_id'] == widget.userId;

      // Ensure controller exists
      final controller = _getOrCreateController(messageId);

      if (isMe) {
        // Current user: Already animated in queue OR shouldn't animate again if re-fetched
        // Mark as completed immediately to prevent default animation
        _completedAnimations.add(messageId);
        // Do NOT reset/forward controller
      } else {
        // Other user: New incoming message, triggers animation
        _completedAnimations.remove(messageId);
        controller.reset();
        controller.forward(from: 0.0);

        // Auto-mark completion after duration
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _completedAnimations.add(messageId);
            // Notify that this message should rebuild (animation complete)
            _rebuildNotifier.value = {messageId};
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _rebuildNotifier.value = {};
            });
          }
        });
      }

      // Insert at top
      currentMessages.insert(0, message);
    }

    debugPrint(
      '[ANIMATION] 🎬 Started animation for ${newMessages.length} messages',
    );

    // Single update triggers ONE rebuild
    widget.messagesNotifier.value = currentMessages;

    // Scroll to top immediately to show new message
    if (widget.scrollController.hasClients) {
      widget.scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// Add older messages to the bottom of the list (pagination)
  /// Used by ChatPage when loading more history
  /// This only rebuilds MessagesList, not the entire ChatPage
  void addOlderMessages(List<Map<String, dynamic>> olderMessages) {
    if (olderMessages.isEmpty) return;

    // Mark as already animated so they don't animate when scrolling up
    final ids = olderMessages.map((m) => m['id'] ?? m['clientId']).toList();
    markMessagesAsAnimated(ids);

    // Append to bottom and trigger list rebuild via Notifier
    final currentMessages = List<Map<String, dynamic>>.from(
      widget.messagesNotifier.value,
    );
    currentMessages.addAll(olderMessages);
    widget.messagesNotifier.value = currentMessages;
  }

  void clearRebuildFlags() {
    _messagesToRebuild.clear();
    _rebuildNotifier.value = {};
  }

  @override
  Widget build(BuildContext context) {
    // Listen to both notifiers
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.messagesNotifier,
        widget.queueMessagesNotifier,
      ]),
      builder: (context, _) {
        final messages = widget.messagesNotifier.value;
        final queueMessages = widget.queueMessagesNotifier.value;
        debugPrint(
          '[UI_TRACE] Builder Run. Queue: ${queueMessages.length}, Messages: ${messages.length}',
        );
        final scrollController = widget.scrollController;
        final userId = widget.userId;
        final isLoadingMore = widget.isLoadingMore;

        // Combine ALL queue messages + ALL confirmed messages
        final allMessagesToDisplay = [...queueMessages, ...messages];

        if (allMessagesToDisplay.isNotEmpty) {
          debugPrint(
            '[MESSAGES LIST] Building list with ${allMessagesToDisplay.length} messages',
          );
          for (int k = 0; k < 3 && k < allMessagesToDisplay.length; k++) {
            debugPrint(
              '[MESSAGES LIST] Item $k: ${allMessagesToDisplay[k]['content']} (ID: ${allMessagesToDisplay[k]['id']})',
            );
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
            itemCount:
                allMessagesToDisplay.length + (isLoadingMore ? 1 : 0) + 1,
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
              if (isLoadingMore &&
                  messageIndex == allMessagesToDisplay.length) {
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

              // Watch the rebuild notifier to check if this specific message needs rebuilding
              return ValueListenableBuilder<Set<dynamic>>(
                valueListenable: _rebuildNotifier,
                builder: (context, rebuildSet, child) {
                  final shouldRebuild = rebuildSet.contains(messageId);

                  // Animate ONLY if it's in the queue (sending), it's the specific new message added by ChatPage,
                  // OR if the controller is explicitly animating (handled by addNewMessage)
                  final bool isControllerAnimating =
                      _messageControllers[messageId]?.isAnimating ?? false;

                  final shouldAnimate =
                      ((isInQueue ||
                              messageId == widget.lastAnimatedMessageId) &&
                          !_completedAnimations.contains(messageId)) ||
                      (isControllerAnimating &&
                          !_completedAnimations.contains(messageId));

                  // Get this message's individual animation controller
                  final messageController = _getOrCreateController(messageId);

                  final currentSenderId = message['sender_id'];

                  // Unified grouping logic: Calculate based on adjacent messages in allMessagesToDisplay
                  // allMessagesToDisplay is [Newest -> Oldest]
                  // Higher index = Older
                  // Lower index = Younger

                  var changedFromOlder = false;
                  var changedToYounger = false;

                  // 1. Check message ABOVE (older message, index + 1)
                  if (messageIndex + 1 < allMessagesToDisplay.length) {
                    final olderMessage = allMessagesToDisplay[messageIndex + 1];
                    changedFromOlder =
                        olderMessage['sender_id'] != currentSenderId;
                  } else {
                    changedFromOlder = true; // No older message
                  }

                  // 2. Check message BELOW (younger message, index - 1)
                  if (messageIndex - 1 >= 0) {
                    final youngerMessage =
                        allMessagesToDisplay[messageIndex - 1];
                    changedToYounger =
                        youngerMessage['sender_id'] != currentSenderId;
                  } else {
                    changedToYounger = true; // No younger message
                  }

                  // Check if this message is from a different day than the next (OLDER) message
                  bool isDifferentDayFromOlder = false;
                  if (messageIndex + 1 < allMessagesToDisplay.length) {
                    final olderMessageTime = getMessageTime(
                      allMessagesToDisplay[messageIndex + 1],
                    );
                    isDifferentDayFromOlder = isDifferentDay(
                      time,
                      olderMessageTime,
                    );
                  } else {
                    // If this is the oldest message in the entire list
                    isDifferentDayFromOlder = true;
                  }

                  // Check if this message is from a different day than the previous (YOUNGER) message
                  bool isDifferentDayFromYounger = false;
                  if (messageIndex - 1 >= 0) {
                    final youngerMessageTime = getMessageTime(
                      allMessagesToDisplay[messageIndex - 1],
                    );
                    isDifferentDayFromYounger = isDifferentDay(
                      time,
                      youngerMessageTime,
                    );
                  } else {
                    // Newest message overall
                    isDifferentDayFromYounger = true;
                  }

                  // Avatar and Bubble Tails show at the START of a group (the TOP/OLDEST message)
                  // Only if sender changed from older OR it's a new day
                  final shouldShowStyles =
                      changedFromOlder || isDifferentDayFromOlder;

                  // Bubble rounding ends at the END of a group (the BOTTOM/NEWEST message)
                  final isNewestInDay = isDifferentDayFromYounger;
                  final senderChangeToNext = changedToYounger;
                  // (named senderChangeToNext but refers to younger message for rounding)

                  // For MessageItem logic
                  final isOldestInDay = isDifferentDayFromOlder;

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
                        isDifferentDayFromNext: isDifferentDayFromOlder,
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
                  if (shouldAnimate) {
                    debugPrint(
                      '[ANIMATION] 🖌️ Rendering animation for $messageId (val: ${messageController.value})',
                    );
                  }

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
      },
    );
  }
}
