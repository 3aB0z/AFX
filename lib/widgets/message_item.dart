import 'package:flutter/material.dart';
import '../config.dart';
import '../widgets/message_bubble.dart';
import '../widgets/profile_avatar.dart';

class MessageItem extends StatelessWidget {
  final Map<String, dynamic> message;
  final int userId;
  final bool shouldShowStyles;
  final bool isOldestInDay;
  final bool isNewestInDay;
  final bool senderChangeToNext;
  final bool isDifferentDayFromNext;
  final VoidCallback? onResend;

  const MessageItem({
    required this.message,
    required this.userId,
    required this.shouldShowStyles,
    required this.isOldestInDay,
    required this.isNewestInDay,
    required this.senderChangeToNext,
    required this.isDifferentDayFromNext,
    this.onResend,
    super.key,
  });

  bool get _isCurrentUser => message['sender_id'] == userId;
  bool get _isAdmin => message['role'] == 'admin';

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

  DateTime _parseMessageTime(Map<String, dynamic> msg) {
    if (msg['created_at'] != null) {
      return DateTime.parse(msg['created_at']).toLocal();
    }
    return DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    if (message['role'] == 'admin') {
       debugPrint('[MESSAGE ITEM] 🛡️ Building admin message: ${message['content']}');
       debugPrint('[MESSAGE ITEM]    - Role in map: ${message['role']}');
       debugPrint('[MESSAGE ITEM]    - _isAdmin getter: $_isAdmin');
    }
    
    final time = _parseMessageTime(message);
    final timeStr = formatMessageTime(time);
    final isAdmin = _isAdmin;
    final isCurrentUser = _isCurrentUser;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Show date separator if day changed
        if (isDifferentDayFromNext)
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: Divider(color: Config.divider, thickness: 1)),
                Padding(
                  padding: const EdgeInsets.only(
                    left: 12,
                    right: 12,
                    bottom: 1,
                  ),
                  child: Text(
                    formatMessageDate(time),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Config.textQuaternary,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: Config.divider, thickness: 1)),
              ],
            ),
          ),
        // Show larger spacing if sender changes from previous message while not oldest in day
        // OR if sender changes to next message (end of group) while not newest in day
        if (shouldShowStyles && !isOldestInDay)
          const SizedBox(height: 8)
        else
          const SizedBox(height: 0),
        Padding(
          padding: EdgeInsets.only(left: 2, right: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: isCurrentUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              // Show loading/error indicator to the left of message (only for current user)
              if (isCurrentUser) ...[
                _buildStatusIndicator(),
                const SizedBox(width: 8),
              ],
              // Show avatar for other users if sender changed OR oldest in day
              if (!isCurrentUser && shouldShowStyles) ...[
                Container(
                  alignment: Alignment.topCenter,
                  margin: const EdgeInsets.only(top: 2),
                  width: 42,
                  height: 42,
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(2),
                        child: ProfileAvatar(
                          fullName: message['sender_name'] ?? 'User',
                          size: 32,
                        ),
                      ),
                      if (isAdmin)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                            child: Center(
                              child: Icon(
                                Icons.verified,
                                size: 13,
                                color: Config.primaryColor,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ] else if (!isCurrentUser && !shouldShowStyles) ...[
                // Empty space to align messages when no avatar
                const SizedBox(width: 42, height: 42),
              ],
              Flexible(
                child: MessageBubble(
                  message: message,
                  isCurrentUser: isCurrentUser,
                  isNewestInDay: isNewestInDay,
                  senderChangeToNext: senderChangeToNext,
                  isAdmin: isAdmin,
                  shouldShowStyles: shouldShowStyles,
                  timeStr: timeStr,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusIndicator() {
    final status = message['status'] ?? 'Sent';
    final isSending = status == 'Sending';
    final isFailed = status == 'Failed';

    if (!isSending && !isFailed) {
      return const SizedBox(width: 0);
    }

    if (isSending) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(Config.primaryColor),
          ),
        ),
      );
    }

    if (isFailed) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: Tooltip(
          message: 'Failed to send. Tap to retry.',
          child: GestureDetector(
            onTap: onResend,
            child: Icon(
              Icons.refresh_rounded,
              size: 18,
              color: Colors.grey[400],
            ),
          ),
        ),
      );
    }

    return const SizedBox(width: 0);
  }
}
