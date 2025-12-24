enum MessageStatus { sending, sent, delivered, read, failed }

class ChatMessage {
  final dynamic id; // Can be int or String from server
  final int senderId;
  final String senderName;
  final String content;
  final String role;
  final DateTime createdAt;
  final MessageStatus
  status; // 'Sending', 'Sent', 'Delivered', 'Read', 'Failed'
  final String? clientId; // Temporary ID for optimistic updates
  final int? prevSenderId;
  final int? nextSenderId;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.role,
    required this.createdAt,
    required this.status,
    this.clientId,
    this.prevSenderId,
    this.nextSenderId,
  });

  /// Convert from Map (API response) to ChatMessage object
  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'],
      senderId: map['sender_id'] as int,
      senderName: map['sender_name'] as String,
      content: map['content'] as String,
      role: map['role'] as String,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at']).toLocal()
          : DateTime.now(),
      status: _parseStatus(map['status'] as String?),
      clientId: map['clientId'] as String?,
      prevSenderId: map['prev_sender_id'] as int?,
      nextSenderId: map['next_sender_id'] as int?,
    );
  }

  /// Convert ChatMessage object back to Map (for API requests/socket emit)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sender_id': senderId,
      'sender_name': senderName,
      'content': content,
      'role': role,
      'created_at': createdAt.toIso8601String(),
      'status': _statusToString(status),
      'clientId': clientId,
      'prev_sender_id': prevSenderId,
      'next_sender_id': nextSenderId,
    };
  }

  /// Create a copy with modified fields (for updates)
  ChatMessage copyWith({
    dynamic id,
    int? senderId,
    String? senderName,
    String? content,
    String? role,
    DateTime? createdAt,
    MessageStatus? status,
    String? clientId,
    int? prevSenderId,
    int? nextSenderId,
  }) {
    return ChatMessage(
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

  static MessageStatus _parseStatus(String? statusStr) {
    switch (statusStr?.toLowerCase()) {
      case 'sending':
        return MessageStatus.sending;
      case 'sent':
        return MessageStatus.sent;
      case 'delivered':
        return MessageStatus.delivered;
      case 'read':
        return MessageStatus.read;
      case 'failed':
        return MessageStatus.failed;
      default:
        return MessageStatus.sent;
    }
  }

  static String _statusToString(MessageStatus status) {
    return status.toString().split('.').last;
  }
}
