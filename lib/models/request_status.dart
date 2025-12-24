// lib/models/request_status.dart
enum RequestStatus {
  pending,
  verified,
  rejected;

  String toDisplayString() {
    switch (this) {
      case RequestStatus.pending:
        return 'Pending';
      case RequestStatus.verified:
        return 'Verified';
      case RequestStatus.rejected:
        return 'Rejected';
    }
  }

  static RequestStatus fromString(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return RequestStatus.pending;
      case 'verified':
        return RequestStatus.verified;
      case 'rejected':
        return RequestStatus.rejected;
      default:
        throw Exception('Invalid request status: $status');
    }
  }
}
