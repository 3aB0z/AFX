import 'package:flutter/material.dart';
import '../config.dart';

class ChatBubbleArrow extends CustomPainter {
  final Color color;
  final bool isRight;
  final double borderRadius;
  final Color borderColor;
  final double borderWidth;

  ChatBubbleArrow({
    required this.color,
    required this.isRight,
    this.borderRadius = 12,
    this.borderColor = const Color.fromARGB(255, 255, 255, 255),
    this.borderWidth = 1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    final path = Path();
    final borderPath = Path();

    if (isRight) {
      // Arrow on the right side (for current user messages)
      path.moveTo(size.width * 0.1, 0);
      path.quadraticBezierTo(size.width * 0.9, 0, 0, size.height);
      path.close();

      borderPath.moveTo(size.width * 0.1, 0);
      borderPath.quadraticBezierTo(
        size.width * 0.9,
        0,
        size.width * 0.1,
        size.height * 0.9,
      );
    } else {
      // Arrow on the left side (for other users)
      path.moveTo(size.width * 0.9, 0);
      path.quadraticBezierTo(size.width * 0.1, 0, size.width, size.height);
      path.close();

      borderPath.moveTo(size.width * 0.9, 0);
      borderPath.quadraticBezierTo(
        size.width * 0.1,
        0,
        size.width * 0.9,
        size.height * 0.9,
      );
    }

    canvas.drawPath(path, paint);
    canvas.drawPath(borderPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isCurrentUser;
  final bool senderChangeToNext;
  final bool isNewestInDay;
  final bool isAdmin;
  final bool shouldShowStyles;
  final String timeStr;

  const MessageBubble({
    required this.message,
    required this.isCurrentUser,
    required this.senderChangeToNext,
    required this.isNewestInDay,
    required this.isAdmin,
    required this.shouldShowStyles,
    required this.timeStr,
    super.key,
  });

  Gradient _getMessageGradient(BuildContext context) {
    if (isCurrentUser) {
      return const LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [Config.messageAdminStart, Config.messageAdminEnd],
      );
    }
    final colors = Config.getOtherMessageGradient(context);
    return LinearGradient(
      begin: Alignment.bottomRight,
      end: Alignment.topLeft,
      colors: colors,
    );
  }

  Color _getBorderColor(BuildContext context) {
    if (isCurrentUser) {
      return Config.messageAdminStart.withAlpha(10);
    }
    return Config.getOtherMessageGradient(context).first.withAlpha(10);
  }

  TextStyle _getMessageNameStyleWithAdmin(BuildContext context) {
    final textColor = isAdmin
        ? (isCurrentUser ? Config.textMessage : Config.primaryColor)
        : (isCurrentUser
              ? Config.textMessage
              : Config.getTextColor(context, level: 2));

    return TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 13,
      color: textColor,
      letterSpacing: 0.1,
      shadows: Config.isDarkMode(context)
          ? []
          : [
              Shadow(
                offset: const Offset(0, 0),
                blurRadius: 4,
                color: textColor.withAlpha(50),
              ),
            ],
    );
  }

  TextStyle _getMessageContentStyle(BuildContext context) {
    return TextStyle(
      fontWeight: FontWeight.normal,
      fontSize: 14,
      color: isCurrentUser ? Config.textMessage : Config.getTextColor(context),
      height: 1.4,
    );
  }

  Color _getMessageTimeColor(BuildContext context) {
    return isCurrentUser
        ? Config.textTimestamp
        : Config.getTextColor(context, level: 3);
  }

  EdgeInsets _getMessageMargin() {
    return EdgeInsets.only(
      top: 4,
      left: isCurrentUser ? 0 : 4,
      right: isCurrentUser ? 4 : 0,
    );
  }

  BorderRadius _getMessageBorderRadius() {
    return BorderRadius.only(
      topLeft: isCurrentUser
          ? Radius.circular(12)
          : (shouldShowStyles ? Radius.circular(0) : Radius.circular(3)),
      topRight: isCurrentUser
          ? (shouldShowStyles ? Radius.circular(0) : Radius.circular(3))
          : Radius.circular(12),
      bottomLeft: isCurrentUser
          ? Radius.circular(12)
          : (senderChangeToNext || isNewestInDay
                ? Radius.circular(12)
                : Radius.circular(3)),
      bottomRight: isCurrentUser
          ? (senderChangeToNext || isNewestInDay
                ? Radius.circular(12)
                : Radius.circular(3))
          : Radius.circular(12),
    );
  }

  List<BoxShadow> _getMessageShadow(BuildContext context) {
    return [
      BoxShadow(
        color: isCurrentUser
            ? Config.messageAdminStart.withAlpha(
                Config.isDarkMode(context) ? 0 : 100,
              )
            : Config.getShadowColor(
                context,
              ).withAlpha(13),
        blurRadius: 6,
        offset: const Offset(0, 0),
        spreadRadius: 0,
      ),
    ];
  }

  String _getMessageContent() {
    return message['content'] ?? '';
  }

  String _getSenderName() {
    return message['sender_name'] ?? 'Admin';
  }

  Widget _buildStatus() {
    final status = message['status'] ?? 'Sent';
    final isSending = status == 'Sending';
    final isFailed = status == 'Failed';

    if (!isSending && !isFailed) {
      return const SizedBox(width: 0);
    }

    if (isFailed && isCurrentUser) {
      return Icon(Icons.error_outline, size: 11, color: Colors.red[300]);
    }

    return SizedBox(width: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.65,
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: _getMessageGradient(context),
              borderRadius: _getMessageBorderRadius(),
              boxShadow: _getMessageShadow(context),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: _getMessageMargin(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (shouldShowStyles && !isCurrentUser) ...[
                  Text(
                    _getSenderName(),
                    style: _getMessageNameStyleWithAdmin(context),
                  ),
                  const SizedBox(height: 6),
                ],
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Column(
                          children: [
                            Text(
                              _getMessageContent(),
                              style: _getMessageContentStyle(context),
                            ),
                            const SizedBox(height: 5),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildStatus(),
                          Text(
                            timeStr,
                            style: TextStyle(
                              fontSize: 10,
                              color: _getMessageTimeColor(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (shouldShowStyles)
          Positioned(
            top: 4,
            right: isCurrentUser ? -10 : null,
            left: isCurrentUser ? null : -10,
            child: CustomPaint(
              size: const Size(16, 10),
              painter: ChatBubbleArrow(
                color: _getMessageGradient(context).colors.last,
                isRight: isCurrentUser,
                borderColor: _getBorderColor(context),
              ),
            ),
          ),
      ],
    );
  }
}
