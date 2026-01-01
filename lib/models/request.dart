import 'package:cloud_firestore/cloud_firestore.dart';

class Request {
  final String id;
  final String name;
  final String email;
  final String status;
  final DateTime createdAt;

  Request({
    required this.id,
    required this.name,
    required this.email,
    required this.status,
    required this.createdAt,
  });

  factory Request.fromJson(Map<String, dynamic> json) {
    return Request(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? 'User',
      email: json['email'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      createdAt: json['created_at'] != null
          ? (json['created_at'] is Timestamp
                ? (json['created_at'] as Timestamp).toDate()
                : DateTime.parse(json['created_at'].toString()))
          : DateTime.now(),
    );
  }
}
