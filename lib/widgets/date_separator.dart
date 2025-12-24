import 'package:flutter/material.dart';
import '../config.dart';

class DateSeparator extends StatelessWidget {
  final DateTime date;

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

  const DateSeparator({required this.date, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: Divider(color: Config.divider, thickness: 1)),
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 1),
            child: Text(
              formatMessageDate(date),
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
    );
  }
}
