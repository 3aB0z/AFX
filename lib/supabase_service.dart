import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

class SupabaseService {
  static final supabase = Supabase.instance.client;
  static const Duration _timeout = Duration(seconds: 10);

  static String _formatError(dynamic error) {
    final errorStr = error.toString().toLowerCase();

    // Timeout errors
    if (errorStr.contains('timeout')) {
      return 'Connection timeout - Please check your internet and Supabase credentials';
    }

    // Connection errors
    if (errorStr.contains('connection refused') ||
        errorStr.contains('connection closed')) {
      return 'Cannot connect to Supabase - Check URL and credentials';
    }

    // Auth errors
    if (errorStr.contains('invalid login credentials') ||
        errorStr.contains('invalid email')) {
      return 'Invalid email or password';
    }
    if (errorStr.contains('user not found')) {
      return 'Account not found - Please create an account first';
    }
    if (errorStr.contains('pending')) {
      return 'Your account is pending approval';
    }
    if (errorStr.contains('rejected')) {
      return 'Your account request was rejected';
    }
    if (errorStr.contains('unauthorized') || errorStr.contains('403')) {
      return 'Unauthorized - Please check your credentials';
    }

    // Network errors
    if (errorStr.contains('network') || errorStr.contains('unreachable')) {
      return 'Network error - Check your internet connection';
    }

    // Database errors
    if (errorStr.contains('no rows') || errorStr.contains('not found')) {
      return 'User data not found in database';
    }
    if (errorStr.contains('duplicate')) {
      return 'Email already exists - Please use a different email';
    }

    // Fallback
    return errorStr.length > 150
        ? '${errorStr.substring(0, 150)}...'
        : errorStr;
  }

  // ========== AUTH / REQUESTS ==========

  /// Send a join request (replaces POST /request)
  static Future<Map<String, dynamic>> sendRequest({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      debugPrint(
        '[Supabase] 📤 Sending join request: name=$name, email=$email',
      );
      final response = await supabase.functions
          .invoke(
            'send-request',
            body: {'name': name, 'email': email, 'password': password},
          )
          .timeout(_timeout);

      final data = response as Map<String, dynamic>;
      debugPrint(
        '[Supabase] ✅ Join request sent successfully: ${data['message']}',
      );

      // Check for error in response
      if (data.containsKey('error') && data['error'] != null) {
        throw Exception(data['error'].toString());
      }

      return data;
    } on TimeoutException catch (_) {
      throw Exception('Request timed out - Please try again');
    } catch (e) {
      throw Exception('Failed to send request: ${_formatError(e)}');
    }
  }

  /// Login user (replaces POST /login)
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      debugPrint('[Supabase] 🔐 Attempting login: email=$email');
      final response = await supabase.functions
          .invoke('login', body: {'email': email, 'password': password})
          .timeout(_timeout);

      final data = response as Map<String, dynamic>;
      debugPrint(
        '[Supabase] ✅ Login successful: id=${data['id']}, role=${data['role']}',
      );

      // Check for error in response
      if (data.containsKey('error') && data['error'] != null) {
        throw Exception(data['error'].toString());
      }

      // Validate response has required fields
      if (!data.containsKey('id') || !data.containsKey('role')) {
        throw Exception('Server returned incomplete user data');
      }

      return data;
    } on TimeoutException catch (_) {
      throw Exception('Login request timed out - Please try again');
    } catch (e) {
      final errorMsg = e.toString();
      if (errorMsg.contains('Invalid login credentials')) {
        throw Exception('Invalid email or password');
      }
      throw Exception('Login failed: ${_formatError(e)}');
    }
  }

  /// Check request status for device (replaces GET /request/check)
  static Future<bool> checkRequestStatus(String email) async {
    try {
      debugPrint('[Supabase] 🔍 Checking request status: email=$email');
      final user = await supabase
          .from('users')
          .select('status')
          .eq('email', email)
          .maybeSingle()
          .timeout(_timeout);
      final exists = user != null;
      debugPrint(
        '[Supabase] ✅ Request status: exists=$exists, status=${user?['status']}',
      );
      return exists;
    } catch (e) {
      // Silently return false on connection errors
      return false;
    }
  }

  /// Get user status and message access (replaces GET /user/status)
  static Future<Map<String, dynamic>> getUserStatus(String userId) async {
    try {
      debugPrint('[Supabase] 📥 Fetching user status: userId=$userId');
      final user = await supabase
          .from('users')
          .select('id, status, can_send_messages')
          .eq('id', userId)
          .single()
          .timeout(_timeout);
      debugPrint(
        '[Supabase] ✅ User status fetched: status=${user['status']}, canSend=${user['can_send_messages']}',
      );
      return {
        'id': user['id'],
        'status': user['status'],
        'canSendMessages': user['can_send_messages'],
      };
    } catch (e) {
      throw Exception('Failed to get user status: ${_formatError(e)}');
    }
  }

  // ========== MESSAGES ==========

  /// Send a message (replaces POST /message via Edge Function)
  static Future<Map<String, dynamic>> sendMessage({
    required String senderId,
    required String content,
  }) async {
    try {
      debugPrint(
        '[Supabase] 💬 Sending message: senderId=$senderId, length=${content.length}',
      );
      final response = await supabase.functions
          .invoke(
            'send-message',
            body: {'content': content},
            headers: {'x-user-id': senderId},
          )
          .timeout(_timeout);
      final responseMap = response as Map<String, dynamic>;
      final msgId = responseMap['data']?['id'];
      final senderName = responseMap['data']?['sender_name'];
      debugPrint(
        '[Supabase] ✅ Message sent: id=$msgId, senderName=$senderName',
      );
      return responseMap;
    } catch (e) {
      throw Exception('Failed to send message: ${_formatError(e)}');
    }
  }

  /// Get messages with pagination (replaces GET /messages)
  static Future<Map<String, dynamic>> getMessages(int page) async {
    try {
      const limit = 20;
      final offset = page * limit;
      debugPrint(
        '[Supabase] 📥 Fetching messages: page=$page, offset=$offset, limit=$limit',
      );

      // Get total count
      final countResponse = await supabase
          .from('messages')
          .select('id')
          .count(CountOption.exact);
      final total = countResponse.count;
      debugPrint('[Supabase] 📊 Total messages: $total');

      // Get paginated messages
      final messages = await supabase
          .from('messages')
          .select(
            'id, sender_id, content, created_at, users!sender_id(name, role)',
          )
          .order('id', ascending: false)
          .range(offset, offset + limit - 1);
      debugPrint('[Supabase] ✅ Fetched ${messages.length} messages');

      // Get prev/next sender for each message
      List<Map<String, dynamic>> messagesWithGrouping = [];
      for (var message in messages) {
        debugPrint(
          '[Supabase] 🔗 Processing message: id=${message['id']}, sender=${message['users']?['name']}',
        );
        final prevSender = await supabase
            .from('messages')
            .select('sender_id')
            .lt('id', message['id'])
            .order('id', ascending: false)
            .limit(1)
            .maybeSingle();

        final nextSender = await supabase
            .from('messages')
            .select('sender_id')
            .gt('id', message['id'])
            .order('id')
            .limit(1)
            .maybeSingle();

        messagesWithGrouping.add({
          'id': message['id'],
          'sender_id': message['sender_id'],
          'sender_name': message['users']?['name'] ?? 'Unknown',
          'role': message['users']?['role'] ?? 'user',
          'content': message['content'],
          'created_at': message['created_at'],
          'prev_sender_id': prevSender?['sender_id'],
          'next_sender_id': nextSender?['sender_id'],
        });
      }

      final hasMore = offset + limit < total;
      debugPrint(
        '[Supabase] ✅ Messages ready: count=${messagesWithGrouping.length}, hasMore=$hasMore, total=$total',
      );
      return {
        'messages': messagesWithGrouping,
        'hasMore': hasMore,
        'total': total,
      };
    } catch (e) {
      throw Exception('Failed to get messages: ${_formatError(e)}');
    }
  }

  /// Real-time message listener - not used currently
  static void messagesStream() {
    // Realtime streaming with Supabase can be added if needed
    // For now, use getMessages() with polling or streams in widgets
  }

  // ========== ADMIN ==========

  /// Verify a user (replaces POST /admin/verify)
  static Future<void> verifyUser({
    required String userId,
    required String token,
  }) async {
    try {
      debugPrint('[Supabase] 👤 Verifying user: userId=$userId');
      await supabase.functions
          .invoke(
            'admin-verify-user',
            body: {'id': userId},
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(_timeout);
      debugPrint('[Supabase] ✅ User verified successfully: userId=$userId');
    } catch (e) {
      throw Exception('Failed to verify user: ${_formatError(e)}');
    }
  }

  /// Reject a user (replaces POST /admin/reject)
  static Future<void> rejectUser({
    required String userId,
    required String token,
  }) async {
    try {
      debugPrint('[Supabase] ❌ Rejecting user: userId=$userId');
      await supabase.functions
          .invoke(
            'admin-reject-user',
            body: {'id': userId},
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(_timeout);
      debugPrint('[Supabase] ✅ User rejected successfully: userId=$userId');
    } catch (e) {
      throw Exception('Failed to reject user: ${_formatError(e)}');
    }
  }

  /// Toggle message access (replaces POST /admin/message-access)
  static Future<void> toggleMessageAccess({
    required String userId,
    required bool canSendMessages,
  }) async {
    try {
      debugPrint(
        '[Supabase] 🔓 Toggling message access: userId=$userId, canSend=$canSendMessages',
      );
      await supabase
          .from('users')
          .update({'can_send_messages': canSendMessages})
          .eq('id', userId)
          .timeout(_timeout);
      debugPrint(
        '[Supabase] ✅ Message access updated: userId=$userId, canSend=$canSendMessages',
      );
    } catch (e) {
      throw Exception('Failed to toggle message access: ${_formatError(e)}');
    }
  }

  /// Update request details (replaces POST /admin/request)
  static Future<void> updateRequest({
    required String userId,
    required Map<String, dynamic> updates,
  }) async {
    try {
      debugPrint(
        '[Supabase] ✏️ Updating request: userId=$userId, updates=$updates',
      );
      await supabase
          .from('users')
          .update(updates)
          .eq('id', userId)
          .timeout(_timeout);
      debugPrint('[Supabase] ✅ Request updated: userId=$userId');
    } catch (e) {
      throw Exception('Failed to update request: ${_formatError(e)}');
    }
  }

  /// Get all requests paginated (replaces Socket: load_requests_all)
  static Future<Map<String, dynamic>> getAllRequests(int page) async {
    try {
      const limit = 20;
      final offset = page * limit;
      debugPrint(
        '[Supabase] 📥 Fetching all requests: page=$page, offset=$offset',
      );

      final countResponse = await supabase
          .from('users')
          .select('id')
          .inFilter('status', ['pending', 'verified', 'rejected'])
          .count(CountOption.exact)
          .timeout(_timeout);

      final requests = await supabase
          .from('users')
          .select(
            'id, name, email, role, status, created_at, can_send_messages',
          )
          .inFilter('status', ['pending', 'verified', 'rejected'])
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1)
          .timeout(_timeout);
      debugPrint('[Supabase] ✅ Fetched ${requests.length} requests');

      final total = countResponse.count;
      debugPrint('[Supabase] 📊 Total requests: $total');
      return {
        'requests': requests,
        'hasMore': offset + limit < total,
        'total': total,
        'page': page,
      };
    } catch (e) {
      throw Exception('Failed to get requests: ${_formatError(e)}');
    }
  }

  /// Get requests by status (replaces Socket: load_requests_by_status)
  static Future<Map<String, dynamic>> getRequestsByStatus(
    String status,
    int page,
  ) async {
    try {
      const limit = 20;
      final offset = page * limit;
      debugPrint(
        '[Supabase] 📥 Fetching requests by status: status=$status, page=$page',
      );

      final countResponse = await supabase
          .from('users')
          .select('id')
          .eq('status', status)
          .count(CountOption.exact)
          .timeout(_timeout);

      final requests = await supabase
          .from('users')
          .select(
            'id, name, email, role, status, created_at, can_send_messages',
          )
          .eq('status', status)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1)
          .timeout(_timeout);
      debugPrint('[Supabase] ✅ Fetched ${requests.length} $status requests');

      final total = countResponse.count;
      debugPrint('[Supabase] 📊 Total $status requests: $total');
      return {
        'requests': requests,
        'hasMore': offset + limit < total,
        'total': total,
        'status': status,
        'page': page,
      };
    } catch (e) {
      throw Exception('Failed to get requests by status: ${_formatError(e)}');
    }
  }

  /// Get admin counts (pending, verified, rejected)
  static Future<Map<String, int>> getAdminCounts() async {
    try {
      debugPrint('[Supabase] 📊 Fetching admin counts...');
      final pendingResponse = await supabase
          .from('users')
          .select('id')
          .eq('status', 'pending')
          .count(CountOption.exact)
          .timeout(_timeout);
      final pendingCount = pendingResponse.count;

      final verifiedResponse = await supabase
          .from('users')
          .select('id')
          .eq('status', 'verified')
          .count(CountOption.exact)
          .timeout(_timeout);
      final verifiedCount = verifiedResponse.count;

      final rejectedResponse = await supabase
          .from('users')
          .select('id')
          .eq('status', 'rejected')
          .count(CountOption.exact)
          .timeout(_timeout);
      final rejectedCount = rejectedResponse.count;

      debugPrint(
        '[Supabase] ✅ Admin counts: pending=$pendingCount, verified=$verifiedCount, rejected=$rejectedCount',
      );
      return {
        'pending': pendingCount,
        'verified': verifiedCount,
        'rejected': rejectedCount,
        'all': pendingCount + verifiedCount + rejectedCount,
      };
    } catch (e) {
      throw Exception('Failed to get admin counts: ${_formatError(e)}');
    }
  }

  /// Stream admin counts in real-time
  static Stream<Map<String, int>> adminCountsStream() async* {
    while (true) {
      try {
        final counts = await getAdminCounts();
        yield counts;
        await Future.delayed(const Duration(seconds: 2));
      } catch (e) {
        yield {'pending': 0, 'verified': 0, 'rejected': 0, 'all': 0};
      }
    }
  }
}
