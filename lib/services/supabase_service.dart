import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../auth.dart';
import '../config.dart';

class SupabaseService {
  static final supabase = Supabase.instance.client;
  static const Duration _timeout = Duration(seconds: 10);

  /// Service role client for admin operations (bypasses RLS)
  /// This uses the service_role key for unrestricted access
  static SupabaseClient? _serviceRoleClient;

  /// Get or create a service role client for admin operations
  /// Used by admins to fetch and manage user requests in production
  static SupabaseClient _getServiceRoleClient() {
    if (_serviceRoleClient != null) {
      return _serviceRoleClient!;
    }

    final serviceKey = Config.supabaseServiceRoleKey;
    if (serviceKey.isEmpty) {
      throw Exception(
        'Service role key not configured. '
        'Please set SUPABASE_SERVICE_ROLE_KEY in your .env file.',
      );
    }

    debugPrint('[SUPABASE] 🔐 Using service role client for admin operations');

    _serviceRoleClient = SupabaseClient(Config.supabaseUrl, serviceKey);

    return _serviceRoleClient!;
  }

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

      debugPrint('[Supabase] 🔍 Raw send-request response: $response');
      debugPrint('[Supabase] 🔍 Response type: ${response.runtimeType}');

      // Extract data from FunctionResponse object
      final dynamic responseData = response is Map<String, dynamic>
          ? response
          : (response as dynamic).data;
      final data = responseData as Map<String, dynamic>;

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

      debugPrint('[Supabase] 🔍 Raw login response: $response');
      debugPrint('[Supabase] 🔍 Response type: ${response.runtimeType}');

      // Extract data from FunctionResponse object
      final dynamic responseData = response is Map<String, dynamic>
          ? response
          : (response as dynamic).data;
      final data = responseData as Map<String, dynamic>;

      debugPrint(
        '[Supabase] ✅ Login successful: id=${data['id']}, role=${data['role']}, token=${data['token']}',
      );

      // Check for error in response
      if (data.containsKey('error') && data['error'] != null) {
        throw Exception(data['error'].toString());
      }

      // Validate response has required fields
      if (!data.containsKey('id') || !data.containsKey('role')) {
        throw Exception('Server returned incomplete user data: $data');
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

      // First, try to get user data from local cache (set during login)
      final cachedLogin = await Auth.getLogin();
      if (cachedLogin != null && cachedLogin['id'].toString() == userId) {
        debugPrint('[Supabase] ✅ Using cached user data');
        return {
          'id': cachedLogin['id'],
          'status': cachedLogin['status'] ?? 'verified',
          'canSendMessages': cachedLogin['can_send_messages'] ?? true,
        };
      }

      // If not cached, query database
      debugPrint('[Supabase] 🔍 User not in cache, querying database...');

      // Convert string userId to int if it's numeric
      int? userIdInt;
      try {
        userIdInt = int.parse(userId);
        debugPrint('[Supabase] 🔢 Parsed userId as int: $userIdInt');
      } catch (e) {
        debugPrint('[Supabase] ⚠️ Could not parse userId as int: $userId');
      }

      debugPrint(
        '[Supabase] 🔍 Querying users table with id=${userIdInt ?? userId}',
      );
      final user = await supabase
          .from('users')
          .select('id, status, can_send_messages')
          .eq('id', userIdInt ?? userId)
          .maybeSingle()
          .timeout(_timeout);

      debugPrint('[Supabase] 📦 Query result: $user');

      if (user == null) {
        debugPrint('[Supabase] ❌ User not found with id: $userId');
        throw Exception('User not found with id: $userId');
      }

      debugPrint(
        '[Supabase] ✅ User status fetched: status=${user['status']}, canSend=${user['can_send_messages']}',
      );
      return {
        'id': user['id'],
        'status': user['status'],
        'canSendMessages': user['can_send_messages'],
      };
    } catch (e) {
      debugPrint('[Supabase] ❌ getUserStatus error: $e');
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
            // Pass role in body so backend can use it for the messages table
            body: {'content': content},
            headers: {'x-user-id': senderId},
          )
          .timeout(_timeout);

      debugPrint('[Supabase] 📦 Raw send-message response: $response');
      debugPrint('[Supabase] 📦 Response type: ${response.runtimeType}');

      // Extract data from FunctionResponse object
      final dynamic responseData = response is Map<String, dynamic>
          ? response
          : (response as dynamic).data;
      final responseMap = responseData as Map<String, dynamic>;

      debugPrint('[Supabase] 📦 Extracted responseMap: $responseMap');

      final msgId = responseMap['data']?['id'];
      final senderName = responseMap['data']?['sender_name'];
      debugPrint(
        '[Supabase] ✅ Message sent: id=$msgId, senderName=$senderName',
      );
      return responseMap;
    } on FunctionException catch (e) {
      debugPrint('[Supabase] ❌ sendMessage FunctionException:');
      debugPrint('[Supabase]    Status: ${e.status}');
      debugPrint('[Supabase]    Reason: ${e.reasonPhrase}');
      debugPrint('[Supabase]    Details: ${e.details}'); // This often contains the JSON body
      rethrow;
    } catch (e) {
      debugPrint('[Supabase] ❌ sendMessage error: $e');
      throw Exception('Failed to send message: ${_formatError(e)}');
    }
  }

  /// Get messages with pagination (replaces GET /messages)
  static Future<Map<String, dynamic>> getMessages(int page) async {
    try {
      const limit = 20;
      debugPrint('[Supabase] 📥 Fetching messages: page=$page, limit=$limit');

      // Call backend endpoint that includes sender info
      final response = await supabase.functions
          .invoke('get-messages', body: {'page': page, 'limit': limit})
          .timeout(_timeout);

      debugPrint('[Supabase] 🔍 Raw get-messages response: $response');

      // Extract data from FunctionResponse object
      final dynamic responseData = response is Map<String, dynamic>
          ? response
          : (response as dynamic).data;
      final data = responseData as Map<String, dynamic>;

      debugPrint('[Supabase] ✅ get-messages completed');

      // Check for error in response
      if (data.containsKey('error') && data['error'] != null) {
        throw Exception(data['error'].toString());
      }

      final messages = List<Map<String, dynamic>>.from(data['messages'] ?? []);
      final hasMore = data['hasMore'] as bool? ?? false;
      final total = data['total'] as int? ?? 0;

      debugPrint(
        '[Supabase] ✅ Messages ready: count=${messages.length}, hasMore=$hasMore, total=$total',
      );

      return {'messages': messages, 'hasMore': hasMore, 'total': total};
    } catch (e) {
      throw Exception('Failed to get messages: ${_formatError(e)}');
    }
  }

  /// Real-time message listener - not used currently
  static void messagesStream() {
    // Realtime streaming with Supabase can be added if needed
    // For now, use getMessages() with polling or streams in widgets
  }

  /// Listen for new messages in real-time using Supabase Realtime
  static RealtimeChannel subscribeToMessages(
    Function(Map<String, dynamic>) onInsert,
    Function(Map<String, dynamic>) onUpdate,
    Function(Map<String, dynamic>) onDelete,
  ) {
    debugPrint(
      '[SUPABASE] 📡 Setting up Realtime subscription for messages table',
    );

    final channel = supabase.realtime.channel('postgres_changes:*:messages:*');

    // Set up all listeners FIRST, then subscribe
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            debugPrint(
              '[SUPABASE] 🆕 INSERT event received: newRecord=${payload.newRecord}',
            );
            try {
              onInsert(payload.newRecord);
            } catch (e) {
              debugPrint('[SUPABASE] ❌ Error in onInsert callback: $e');
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            debugPrint(
              '[SUPABASE] ✏️ UPDATE event received: newRecord=${payload.newRecord}',
            );
            try {
              onUpdate(payload.newRecord);
            } catch (e) {
              debugPrint('[SUPABASE] ❌ Error in onUpdate callback: $e');
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            debugPrint(
              '[SUPABASE] 🗑️ DELETE event received: oldRecord=${payload.oldRecord}',
            );
            try {
              onDelete(payload.oldRecord);
            } catch (e) {
              debugPrint('[SUPABASE] ❌ Error in onDelete callback: $e');
            }
          },
        )
        .subscribe((status, error) {
          if (error != null) {
            debugPrint('[SUPABASE] ❌ Channel subscription error: $error');
          } else {
            debugPrint('[SUPABASE] ✅ Channel subscription status: $status');
          }
        });

    return channel;
  }

  /// Unsubscribe from messages real-time channel
  static Future<void> unsubscribeFromMessages(RealtimeChannel channel) async {
    debugPrint('[SUPABASE] 🔌 Unsubscribing from messages channel');
    await supabase.realtime.removeChannel(channel);
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
      debugPrint('[Supabase] ═══════════════════════════════════════════════');
      debugPrint(
        '[Supabase] 📥 Fetching requests by status: status=$status, page=$page',
      );
      debugPrint(
        '[Supabase]    offset=$offset, limit=$limit, timeout=${_timeout.inSeconds}s',
      );

      // Use service role client to bypass RLS
      debugPrint('[Supabase] 🔐 Initializing service role client...');
      final serviceClient = _getServiceRoleClient();
      debugPrint('[Supabase] ✅ Service role client ready');

      // Query 1: Get count
      debugPrint('[Supabase] ▶️ STEP 1: Querying count for status: $status');
      debugPrint('[Supabase]    Query: select id where status=$status');

      final countResponse = await serviceClient
          .from('users')
          .select('id')
          .eq('status', status)
          .count(CountOption.exact)
          .timeout(_timeout);

      debugPrint('[Supabase] ✅ Count query SUCCESS');
      final total = countResponse.count;
      debugPrint('[Supabase] 📊 Count result: total=$total');

      // Query 2: Get data
      debugPrint('[Supabase] ▶️ STEP 2: Querying data for status: $status');
      debugPrint(
        '[Supabase]    Query: select [id,name,email,role,status,created_at,can_send_messages]',
      );
      debugPrint('[Supabase]    WHERE status=$status ORDER BY created_at DESC');
      debugPrint('[Supabase]    RANGE $offset to ${offset + limit - 1}');

      final requests = await serviceClient
          .from('users')
          .select(
            'id, name, email, role, status, created_at, can_send_messages',
          )
          .eq('status', status)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1)
          .timeout(_timeout);

      debugPrint('[Supabase] ✅ Data query SUCCESS');
      debugPrint('[Supabase] 📋 Fetched ${requests.length} records');

      if (requests.isNotEmpty) {
        debugPrint('[Supabase] 📄 First record sample:');
        final first = requests[0];
        debugPrint('[Supabase]    - id: ${first['id']}');
        debugPrint('[Supabase]    - name: ${first['name']}');
        debugPrint('[Supabase]    - email: ${first['email']}');
        debugPrint('[Supabase]    - status: ${first['status']}');
      }

      final result = {
        'requests': requests,
        'hasMore': offset + limit < total,
        'total': total,
        'status': status,
        'page': page,
      };

      debugPrint('[Supabase] 📤 FINAL RESULT:');
      debugPrint('[Supabase]    - requests.length: ${requests.length}');
      debugPrint('[Supabase]    - total: $total');
      debugPrint('[Supabase]    - hasMore: ${offset + limit < total}');
      debugPrint('[Supabase] ═══════════════════════════════════════════════');
      return result;
    } catch (e) {
      debugPrint('[Supabase] ═══════════════════════════════════════════════');
      debugPrint('[Supabase] ❌ ERROR in getRequestsByStatus');
      debugPrint('[Supabase]    Error type: ${e.runtimeType}');
      debugPrint('[Supabase]    Error message: $e');
      debugPrint('[Supabase]    Formatted error: ${_formatError(e)}');
      debugPrint('[Supabase] ═══════════════════════════════════════════════');
      rethrow;
    }
  }

  /// Get all requests with pagination (for requests page)
  static Future<Map<String, dynamic>> getAllRequestsByPagination(
    int page,
  ) async {
    try {
      const limit = 20;
      final offset = page * limit;

      debugPrint(
        '[Supabase] 📥 Fetching all requests: page=$page, offset=$offset, limit=$limit',
      );

      final serviceClient = _getServiceRoleClient();

      // Get count
      final countResponse = await serviceClient
          .from('users')
          .select('id')
          .neq('status', 'admin') // Exclude admin users
          .count(CountOption.exact)
          .timeout(_timeout);
      final total = countResponse.count;

      debugPrint('[Supabase] ✅ Total requests: $total');

      // Get paginated data
      final requests = await serviceClient
          .from('users')
          .select(
            'id, name, email, role, status, created_at, can_send_messages',
          )
          .neq('status', 'admin') // Exclude admin users
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1)
          .timeout(_timeout);

      debugPrint(
        '[Supabase] ✅ Fetched ${requests.length} records for page $page',
      );

      return {
        'requests': requests,
        'hasMore': offset + limit < total,
        'total': total,
        'page': page,
      };
    } catch (e) {
      debugPrint('[Supabase] ❌ ERROR in getAllRequestsByPagination');
      debugPrint('[Supabase]    Error: ${_formatError(e)}');
      rethrow;
    }
  }

  /// Get admin counts for pending, verified, and rejected users
  static Future<Map<String, int>> getAdminCounts() async {
    try {
      debugPrint('[Supabase] 📊 Getting admin counts...');

      // Use service role client to bypass RLS
      final serviceClient = _getServiceRoleClient();
      debugPrint('[Supabase] ✅ Service role client initialized');

      final pendingResponse = await serviceClient
          .from('users')
          .select('id')
          .eq('status', 'pending')
          .count(CountOption.exact)
          .timeout(_timeout);
      final pendingCount = pendingResponse.count;
      debugPrint('[Supabase] 📊 Pending count: $pendingCount');

      final verifiedResponse = await serviceClient
          .from('users')
          .select('id')
          .eq('status', 'verified')
          .count(CountOption.exact)
          .timeout(_timeout);
      final verifiedCount = verifiedResponse.count;
      debugPrint('[Supabase] 📊 Verified count: $verifiedCount');

      final rejectedResponse = await serviceClient
          .from('users')
          .select('id')
          .eq('status', 'rejected')
          .count(CountOption.exact)
          .timeout(_timeout);
      final rejectedCount = rejectedResponse.count;
      debugPrint('[Supabase] 📊 Rejected count: $rejectedCount');

      final allCount = pendingCount + verifiedCount + rejectedCount;
      debugPrint(
        '[Supabase] ✅ Admin counts: pending=$pendingCount, verified=$verifiedCount, rejected=$rejectedCount, all=$allCount',
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

  /// Diagnostic: Get all user statuses in database to find what's actually stored
  static Future<Map<String, dynamic>> getAllUserStatuses() async {
    try {
      debugPrint('[Supabase] ═══════════════════════════════════════════════');
      debugPrint(
        '[Supabase] 🔍 DIAGNOSTIC: Fetching all users to check statuses...',
      );

      // Use service role client to bypass RLS
      final serviceClient = _getServiceRoleClient();
      debugPrint('[Supabase] ✅ Service role client initialized');

      debugPrint(
        '[Supabase] ▶️ Executing: select id,name,email,status,role,created_at limit(100)',
      );
      final allUsers = await serviceClient
          .from('users')
          .select('id, name, email, status, role, created_at')
          .limit(100)
          .timeout(_timeout);

      debugPrint('[Supabase] ✅ Query SUCCESS');
      debugPrint('[Supabase] 📋 Total users found: ${allUsers.length}');

      if (allUsers.isEmpty) {
        debugPrint(
          '[Supabase] ⚠️ Query returned 0 users - database might be empty',
        );
        debugPrint(
          '[Supabase] ═══════════════════════════════════════════════',
        );
        return {'totalUsers': 0, 'statusDistribution': {}, 'allUsers': []};
      }

      // Group by status
      final statusGroups = <String, List<Map<String, dynamic>>>{};
      for (final user in allUsers) {
        final status = user['status'] ?? 'null';
        statusGroups.putIfAbsent(status, () => []).add(user);
      }

      debugPrint('[Supabase] 📊 Status distribution:');
      statusGroups.forEach((status, users) {
        debugPrint('[Supabase]    - status="$status": ${users.length} users');
        if (users.length <= 5) {
          for (final user in users) {
            debugPrint(
              '[Supabase]      • id=${user['id']}, name=${user['name']}, email=${user['email']}',
            );
          }
        }
      });

      debugPrint('[Supabase] ═══════════════════════════════════════════════');
      return {
        'totalUsers': allUsers.length,
        'statusDistribution': statusGroups.map((k, v) => MapEntry(k, v.length)),
        'allUsers': allUsers,
      };
    } catch (e) {
      debugPrint('[Supabase] ═══════════════════════════════════════════════');
      debugPrint('[Supabase] ❌ ERROR in getAllUserStatuses');
      debugPrint('[Supabase]    Error type: ${e.runtimeType}');
      debugPrint('[Supabase]    Error message: $e');
      debugPrint('[Supabase]    Formatted error: ${_formatError(e)}');
      debugPrint('[Supabase] ═══════════════════════════════════════════════');
      throw Exception('Failed to get all user statuses: ${_formatError(e)}');
    }
  }
}
