/// Message status enum for tracking message delivery and read status
enum MessageStatus {
  /// Message is being sent to server
  sending,

  /// Message was successfully sent to server
  sent,

  /// Message was delivered to recipients
  delivered,

  /// Message was read by recipient
  read,

  /// Message failed to send
  failed,
}

/// ChatMessage model with comprehensive status and synchronization support
class ChatMessage {
  /// Permanent server-assigned message ID (null while 'Sending')
  final int? id;

  /// Temporary client-generated ID for optimistic updates (UUID string)
  /// Used to track message before server assigns permanent ID
  final String clientId;

  /// ID of the user who sent the message
  final int senderId;

  /// Name of the sender
  final String senderName;

  /// Role of the sender (admin, user, etc.)
  final String role;

  /// Message content
  final String content;

  /// When the message was created locally on client
  final DateTime createdAtLocal;

  /// Server timestamp - authoritative source for message ordering
  /// Initially null, set when server responds with confirmation
  final DateTime? createdAtServer;

  /// Current delivery/read status of the message
  final MessageStatus status;

  /// Previous sender ID in the message list (for grouping)
  final int? prevSenderId;

  /// Next sender ID in the message list (for grouping)
  final int? nextSenderId;

  ChatMessage({
    this.id,
    required this.clientId,
    required this.senderId,
    required this.senderName,
    required this.role,
    required this.content,
    required this.createdAtLocal,
    this.createdAtServer,
    required this.status,
    this.prevSenderId,
    this.nextSenderId,
  });

  /// Creates a copy of this message with optional field updates
  ChatMessage copyWith({
    int? id,
    String? clientId,
    int? senderId,
    String? senderName,
    String? role,
    String? content,
    DateTime? createdAtLocal,
    DateTime? createdAtServer,
    MessageStatus? status,
    int? prevSenderId,
    int? nextSenderId,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAtLocal: createdAtLocal ?? this.createdAtLocal,
      createdAtServer: createdAtServer ?? this.createdAtServer,
      status: status ?? this.status,
      prevSenderId: prevSenderId ?? this.prevSenderId,
      nextSenderId: nextSenderId ?? this.nextSenderId,
    );
  }

  /// Convert ChatMessage to Map for HTTP requests to server
  Map<String, dynamic> toJson() {
    return {
      'clientId': clientId,
      'sender_id': senderId,
      'sender_name': senderName,
      'role': role,
      'content': content,
      'created_at': createdAtLocal.toIso8601String(),
    };
  }

  /// Convert server response Map to ChatMessage
  /// Called when server confirms message was received and assigned ID
  factory ChatMessage.fromServerResponse(
    Map<String, dynamic> json, {
    required String clientId,
  }) {
    return ChatMessage(
      id: json['id'] as int,
      clientId: clientId,
      senderId: json['sender_id'] as int,
      senderName: json['sender_name'] as String? ?? 'Unknown',
      role: json['role'] as String? ?? 'user',
      content: json['content'] as String,
      createdAtLocal: DateTime.parse(json['created_at'] as String),
      createdAtServer: DateTime.parse(json['created_at'] as String),
      status: MessageStatus.sent,
      prevSenderId: json['prev_sender_id'] as int?,
      nextSenderId: json['next_sender_id'] as int?,
    );
  }

  /// Parse message from paginated list response
  factory ChatMessage.fromPaginatedResponse(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as int,
      clientId:
          'server_${json['id']}', // Server messages don't need client tracking
      senderId: json['sender_id'] as int,
      senderName: json['sender_name'] as String? ?? 'Unknown',
      role: json['role'] as String? ?? 'user',
      content: json['content'] as String,
      createdAtLocal: DateTime.parse(json['created_at'] as String),
      createdAtServer: DateTime.parse(json['created_at'] as String),
      status: MessageStatus.sent,
      prevSenderId: json['prev_sender_id'] as int?,
      nextSenderId: json['next_sender_id'] as int?,
    );
  }

  /// Convert back to Map for internal list storage (backward compatible)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'clientId': clientId,
      'sender_id': senderId,
      'sender_name': senderName,
      'role': role,
      'content': content,
      'created_at': createdAtLocal.toIso8601String(),
      'created_at_server': createdAtServer?.toIso8601String(),
      'status': status.toString().split('.').last,
      'prev_sender_id': prevSenderId,
      'next_sender_id': nextSenderId,
    };
  }

  /// Parse from internal Map storage
  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    final statusStr = (map['status'] as String?) ?? 'sent';
    final status = MessageStatus.values.firstWhere(
      (e) => e.toString().split('.').last == statusStr,
      orElse: () => MessageStatus.sent,
    );

    return ChatMessage(
      id: map['id'] as int?,
      clientId:
          (map['clientId'] as String?) ??
          'client_${DateTime.now().millisecondsSinceEpoch}',
      senderId: map['sender_id'] as int,
      senderName: map['sender_name'] as String? ?? 'Unknown',
      role: map['role'] as String? ?? 'user',
      content: map['content'] as String,
      createdAtLocal: DateTime.parse(map['created_at'] as String),
      createdAtServer: map['created_at_server'] != null
          ? DateTime.parse(map['created_at_server'] as String)
          : null,
      status: status,
      prevSenderId: map['prev_sender_id'] as int?,
      nextSenderId: map['next_sender_id'] as int?,
    );
  }

  @override
  String toString() =>
      'ChatMessage(id: $id, clientId: $clientId, status: $status, senderId: $senderId)';
}
