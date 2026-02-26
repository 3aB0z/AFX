import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageStatus { sending, sent, delivered, read, failed }

class ChatMessage {
  final String id; // Firestore document ID
  final String senderId; // Firebase Auth UID
  final String senderName;
  final String content;
  final String role;
  final DateTime createdAt;
  final MessageStatus
  status; // 'Sending', 'Sent', 'Delivered', 'Read', 'Failed'
  final String? clientId; // Temporary ID for optimistic updates
  final String? prevSenderId;
  final String? nextSenderId;
  final bool encrypted;
  final String? contentHash;

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
    this.encrypted = false,
    this.contentHash,
  });

  /// Convert from Map (API response) to ChatMessage object
  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id']?.toString() ?? '',
      senderId: map['sender_id']?.toString() ?? '',
      senderName: map['sender_name'] as String? ?? 'User',
      content: map['content'] as String? ?? '',
      role: map['role'] as String? ?? 'user',
      createdAt: map['created_at'] != null
          ? (map['created_at'] is Timestamp
                ? (map['created_at'] as Timestamp).toDate()
                : (map['created_at'] is String
                      ? DateTime.parse(map['created_at'].toString()).toLocal()
                      : DateTime.now()))
          : DateTime.now(),
      status: _parseStatus(map['status'] as String?),
      clientId: map['clientId'] as String? ?? map['client_id'] as String?,
      prevSenderId: map['prev_sender_id']?.toString(),
      nextSenderId: map['next_sender_id']?.toString(),
      encrypted: map['encrypted'] == true,
      contentHash: map['content_hash'] as String?,
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
      'client_id': clientId,
      'prev_sender_id': prevSenderId,
      'next_sender_id': nextSenderId,
      'encrypted': encrypted,
      'content_hash': contentHash,
    };
  }

  /// Create a copy with modified fields (for updates)
  ChatMessage copyWith({
    String? id,
    String? senderId,
    String? senderName,
    String? content,
    String? role,
    DateTime? createdAt,
    MessageStatus? status,
    String? clientId,
    String? prevSenderId,
    String? nextSenderId,
    bool? encrypted,
    String? contentHash,
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
      encrypted: encrypted ?? this.encrypted,
      contentHash: contentHash ?? this.contentHash,
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
