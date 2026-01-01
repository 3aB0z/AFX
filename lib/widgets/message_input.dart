import 'package:flutter/material.dart';
import '../config.dart';

class MessageInput extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool enabled;

  const MessageInput({
    required this.controller,
    required this.onSend,
    required this.enabled,
    super.key,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Config.getDividerColor(context), width: 1),
        ),
        color: Config.getSurfaceColor(context),
      ),
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minHeight: 60, maxHeight: 80),
      child: widget.enabled
          ? IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Config.getBackgroundColor(context),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(24),
                          bottomLeft: Radius.circular(24),
                        ),
                        border: Border(
                          left: BorderSide(
                            color: Config.getDividerColor(context),
                            width: 1,
                          ),
                          top: BorderSide(
                            color: Config.getDividerColor(context),
                            width: 1,
                          ),
                          bottom: BorderSide(
                            color: Config.getDividerColor(context),
                            width: 1,
                          ),
                          right: BorderSide.none,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(24),
                          bottomLeft: Radius.circular(24),
                        ),
                        child: TextField(
                          controller: widget.controller,
                          enabled: widget.enabled,
                          cursorColor: Config.primaryColor,
                          style: TextStyle(color: Config.getTextColor(context)),
                          decoration: InputDecoration(
                            hintText: 'Type a message',
                            hintStyle: TextStyle(
                              color: Config.getTextColor(context, level: 3),
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: true,
                            fillColor: Colors.transparent,
                            isDense: true,
                            contentPadding: EdgeInsets.only(
                              left: 8,
                              right: 2,
                              top: 12,
                              bottom: 12,
                            ),
                          ),
                          maxLines: null,
                          minLines: 1,
                          onSubmitted: (_) =>
                              widget.enabled ? widget.onSend() : null,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Material(
                      borderRadius: BorderRadius.horizontal(
                        right: Radius.circular(24),
                      ),
                      clipBehavior: Clip.antiAlias,
                      type: MaterialType.canvas,
                      color: Config.getBackgroundColor(context),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.horizontal(
                            right: Radius.circular(24),
                          ),
                          border: Border(
                            top: BorderSide(
                              color: Config.getDividerColor(context),
                              width: 1,
                            ),
                            bottom: BorderSide(
                              color: Config.getDividerColor(context),
                              width: 1,
                            ),
                            right: BorderSide(
                              color: Config.getDividerColor(context),
                              width: 1,
                            ),
                            left: BorderSide.none,
                          ),
                        ),
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: widget.controller,
                          builder: (context, value, child) {
                            final bool canSend =
                                widget.enabled && value.text.isNotEmpty;
                            return InkWell(
                              customBorder: RoundedRectangleBorder(
                                borderRadius: BorderRadius.horizontal(
                                  right: Radius.circular(23),
                                ),
                              ),
                              onTap: canSend ? widget.onSend : null,
                              highlightColor: Config.primaryColor.withAlpha(25),
                              splashColor: Config.primaryColor.withAlpha(50),
                              hoverColor: Config.primaryColor.withAlpha(10),
                              child: Icon(
                                Icons.send_rounded,
                                color: canSend
                                    ? Config.primaryColor
                                    : Config.getTextColor(context, level: 3),
                                size: 24,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : SizedBox(
              height: 50,
              child: Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 26,
                    child: Icon(
                      Icons.lock_outline,
                      size: 26,
                      color: Config.getTextColor(context, level: 3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'You cannot send messages in this chat.',
                      style: TextStyle(
                        color: Config.getTextColor(context, level: 2),
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
