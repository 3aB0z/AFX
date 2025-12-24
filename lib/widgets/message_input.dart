import 'package:flutter/material.dart';
import '../config.dart';

class MessageInput extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool enabled;
  final String? disabledReason;

  const MessageInput({
    required this.controller,
    required this.onSend,
    required this.enabled,
    this.disabledReason,
    super.key,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  @override
  Widget build(BuildContext context) {
    if (!widget.enabled && widget.disabledReason != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 32, color: Config.textHint),
              const SizedBox(height: 8),
              Text(
                widget.disabledReason!,
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
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Config.borderSecondary, width: 1),
        ),
        color: const Color.fromARGB(255, 250, 250, 250),
      ),
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(maxHeight: 88),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: widget.controller,
        builder: (context, value, child) {
          final bool hasText = value.text.isNotEmpty;
          final bool canSend = widget.enabled && hasText;
          return TextField(
            controller: widget.controller,
            enabled: widget.enabled,
            cursorColor: Config.primaryColor,
            decoration: InputDecoration(
              hintText: 'Type a message',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide(color: Config.borderSecondary, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide(color: Config.borderSecondary, width: 1),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide(
                  color: Config.borderSecondary.withAlpha(100),
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide(
                  color: Config.primaryColor.withAlpha(128),
                  width: 1.5,
                ),
              ),
              filled: true,
              fillColor: Config.background,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              suffixIcon: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.send_rounded,
                  color: canSend ? Config.primaryColor : Config.textHint,
                  size: 24,
                ),
                onPressed: canSend ? widget.onSend : null,
              ),
            ),
            maxLines: null,
            minLines: 1,
            onSubmitted: (_) => widget.enabled ? widget.onSend() : null,
          );
        },
      ),
    );
  }
}
