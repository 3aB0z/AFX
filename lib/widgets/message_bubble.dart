import 'package:flutter/material.dart';
import '../config.dart';
import '../services/security_service.dart';

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

class MessageBubble extends StatefulWidget {
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

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  String? _decryptedContent;
  bool _isDecrypting = false;

  @override
  void initState() {
    super.initState();
    SecurityService.isKeyReady.addListener(_decryptIfNeeded);
    _decryptIfNeeded();
  }

  @override
  void didUpdateWidget(MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message['content'] != oldWidget.message['content'] ||
        widget.message['id'] != oldWidget.message['id']) {
      _decryptIfNeeded();
    }
  }

  @override
  void dispose() {
    SecurityService.isKeyReady.removeListener(_decryptIfNeeded);
    super.dispose();
  }

  void _decryptIfNeeded() {
    if (!mounted) return;

    final bool isEncrypted = widget.message['encrypted'] == true;
    final String content = widget.message['content'] ?? '';
    final String messageId =
        (widget.message['id'] ?? widget.message['clientId'] ?? '').toString();

    if (isEncrypted && messageId.isNotEmpty) {
      // 1. Try synchronous cache check first to avoid flicker
      final cached = SecurityService.tryGetCachedDecryptedContent(messageId);
      if (cached != null) {
        setState(() {
          _decryptedContent = cached;
          _isDecrypting = false;
        });
        return;
      }

      // 2. Check if key is available
      if (!SecurityService.isKeyReady.value) {
        setState(() {
          _isDecrypting = true;
          _decryptedContent = null;
        });
        return;
      }

      // 3. Perform local decryption (Synchronous!)
      final decrypted = SecurityService.decryptLocal(content);
      if (decrypted != null && !decrypted.contains('[Encrypted Message]')) {
        setState(() {
          _decryptedContent = decrypted;
          _isDecrypting = false;
          SecurityService.addToDecryptionCache(messageId, decrypted);
        });
      } else {
        // Permanent failure (e.g. invalid format or truly wrong key)
        setState(() {
          _isDecrypting = false;
          _decryptedContent = '[Encrypted]';
        });
      }
    } else {
      setState(() {
        _decryptedContent = null;
        _isDecrypting = false;
      });
    }
  }

  Gradient _getMessageGradient(BuildContext context) {
    if (widget.isCurrentUser) {
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
    if (widget.isCurrentUser) {
      return Config.messageAdminStart.withAlpha(10);
    }
    return Config.getOtherMessageGradient(context).first.withAlpha(10);
  }

  TextStyle _getMessageNameStyleWithAdmin(BuildContext context) {
    final textColor = widget.isAdmin
        ? (widget.isCurrentUser ? Config.textMessage : Config.primaryColor)
        : (widget.isCurrentUser
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
      color: widget.isCurrentUser
          ? Config.textMessage
          : Config.getTextColor(context),
      height: 1.4,
    );
  }

  Color _getMessageTimeColor(BuildContext context) {
    return widget.isCurrentUser
        ? Config.textTimestamp
        : Config.getTextColor(context, level: 3);
  }

  EdgeInsets _getMessageMargin() {
    return EdgeInsets.only(
      top: 4,
      left: widget.isCurrentUser ? 0 : 4,
      right: widget.isCurrentUser ? 4 : 0,
    );
  }

  BorderRadius _getMessageBorderRadius() {
    return BorderRadius.only(
      topLeft: widget.isCurrentUser
          ? Radius.circular(12)
          : (widget.shouldShowStyles ? Radius.circular(0) : Radius.circular(3)),
      topRight: widget.isCurrentUser
          ? (widget.shouldShowStyles ? Radius.circular(0) : Radius.circular(3))
          : Radius.circular(12),
      bottomLeft: widget.isCurrentUser
          ? Radius.circular(12)
          : (widget.senderChangeToNext || widget.isNewestInDay
                ? Radius.circular(12)
                : Radius.circular(3)),
      bottomRight: widget.isCurrentUser
          ? (widget.senderChangeToNext || widget.isNewestInDay
                ? Radius.circular(12)
                : Radius.circular(3))
          : Radius.circular(12),
    );
  }

  List<BoxShadow> _getMessageShadow(BuildContext context) {
    return [
      BoxShadow(
        color: widget.isCurrentUser
            ? Config.messageAdminStart.withAlpha(
                Config.isDarkMode(context) ? 0 : 100,
              )
            : Config.getShadowColor(context).withAlpha(13),
        blurRadius: 6,
        offset: const Offset(0, 0),
        spreadRadius: 0,
      ),
    ];
  }

  String _getMessageContent() {
    if (_decryptedContent != null) return _decryptedContent!;

    // If it's encrypted but we haven't decrypted it yet, return empty
    if (widget.message['encrypted'] == true) {
      return '';
    }

    return widget.message['content'] ?? '';
  }

  String _getSenderName() {
    return widget.message['sender_name'] ?? 'Admin';
  }

  Widget _buildStatus() {
    final status = widget.message['status'] ?? 'Sent';
    final isSending = status == 'Sending';
    final isFailed = status == 'Failed';

    if (!isSending && !isFailed) {
      return const SizedBox(width: 0);
    }

    if (isFailed && widget.isCurrentUser) {
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
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.shouldShowStyles && !widget.isCurrentUser) ...[
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_isDecrypting)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 4),
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Config.primaryColor,
                                    ),
                                  ),
                                )
                              else
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
                              widget.timeStr,
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
        ),
        if (widget.shouldShowStyles)
          Positioned(
            top: 4,
            right: widget.isCurrentUser ? -10 : null,
            left: widget.isCurrentUser ? null : -10,
            child: CustomPaint(
              size: const Size(16, 10),
              painter: ChatBubbleArrow(
                color: _getMessageGradient(context).colors.last,
                isRight: widget.isCurrentUser,
                borderColor: _getBorderColor(context),
              ),
            ),
          ),
      ],
    );
  }
}
