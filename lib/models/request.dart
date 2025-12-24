class Request {
  final int id;
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
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}