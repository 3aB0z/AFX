import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FirebaseService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ===========================================================================
  // AUTHENTICATION
  // ===========================================================================

  static User? get currentUser => _auth.currentUser;
  static String? getCurrentUserId() => _auth.currentUser?.uid;

  // Local Storage Keys
  static const String _keyCanSendMessages = 'can_send_messages';
  static const String _keyUserRole = 'user_role';

  /// Save user config locally for faster startup
  static Future<void> saveUserConfig({
    required bool canSendMessages,
    required String role,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCanSendMessages, canSendMessages);
    await prefs.setString(_keyUserRole, role);
    debugPrint(
      '[FIREBASE_SERVICE] 💾 Saved local config: canSend=$canSendMessages, role=$role',
    );
  }

  /// Get local user config
  static Future<Map<String, dynamic>> getUserConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'can_send_messages': prefs.getBool(_keyCanSendMessages) ?? false,
      'role': prefs.getString(_keyUserRole) ?? 'user',
    };
  }

  static Future<UserCredential> login(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  static Future<UserCredential> signUp(
    String email,
    String password,
    String name,
  ) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    if (credential.user != null) {
      // Create user document in Firestore
      await _db.collection('users').doc(credential.user!.uid).set({
        'id': credential.user!.uid, // Store UID as ID
        'name': name,
        'email': email,
        'role': 'user', // Default role
        'status': 'pending',
        'created_at': FieldValue.serverTimestamp(),
        'can_send_messages': false,
      });
    }

    return credential;
  }

  static Future<void> logout() async {
    await _auth.signOut();
  }

  // ===========================================================================
  // MESSAGES
  // ===========================================================================

  static Stream<QuerySnapshot<Map<String, dynamic>>> getMessagesStream({
    int limit = 20,
    DocumentSnapshot? startAfterDocument,
  }) {
    Query<Map<String, dynamic>> query = _db
        .collection('messages')
        .orderBy('created_at', descending: true);

    if (startAfterDocument != null) {
      query = query.startAfterDocument(startAfterDocument);
    }

    return query.limit(limit).snapshots();
  }

  static Future<List<Map<String, dynamic>>> getOldMessages({
    required int limit,
    required DateTime lastMessageTimestamp,
  }) async {
    final snapshot = await _db
        .collection('messages')
        .orderBy('created_at', descending: true)
        .startAfter([Timestamp.fromDate(lastMessageTimestamp)])
        .limit(limit)
        .get();

    return snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
  }

  static String generateMessageId() {
    return _db.collection('messages').doc().id;
  }

  static Future<void> sendMessage({
    required String senderId,
    required String senderName,
    required String content,
    required String role,
    String? docId, // Optional: Pre-generated ID
  }) async {
    final messageData = {
      'sender_id': senderId,
      'sender_name': senderName,
      'content': content,
      'role': role,
      'created_at': FieldValue.serverTimestamp(),
    };

    if (docId != null) {
      // Use pre-generated ID
      await _db.collection('messages').doc(docId).set(messageData);
    } else {
      // Auto-generate ID (fallback)
      await _db.collection('messages').add(messageData);
    }
  }

  // ===========================================================================
  // USER STATUS & REQUESTS
  // ===========================================================================

  static Future<Map<String, dynamic>?> getUserData(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> getUserDataStream(
    String uid,
  ) {
    return _db.collection('users').doc(uid).snapshots();
  }

  static Future<void> updateUserStatus(String uid, String status) async {
    await _db.collection('users').doc(uid).update({
      'status': status,
      // User stays muted by default when verified
      if (status == 'rejected') ...{
        'can_send_messages': false,
        'rejected_at': FieldValue.serverTimestamp(),
      },
    });
  }

  static Future<void> resubmitRequest(String uid) async {
    await _db.collection('users').doc(uid).update({
      'status': 'pending',
      'can_send_messages': false,
      // We don't clear rejected_at, so we can keep history if needed,
      // but status change will let user in to the pending screen
    });
  }

  static Future<Map<String, int>> getAllStatusCounts() async {
    try {
      final results = await Future.wait([
        _db
            .collection('users')
            .where('status', isEqualTo: 'pending')
            .count()
            .get(),
        _db
            .collection('users')
            .where('status', isEqualTo: 'verified')
            .count()
            .get(),
        _db
            .collection('users')
            .where('status', isEqualTo: 'rejected')
            .count()
            .get(),
        _db.collection('users').count().get(),
      ]);

      return {
        'pending': results[0].count ?? 0,
        'verified': results[1].count ?? 0,
        'rejected': results[2].count ?? 0,
        'all': results[3].count ?? 0,
      };
    } catch (e) {
      debugPrint('[FIREBASE_SERVICE] ❌ Error fetching counts: $e');
      return {'pending': 0, 'verified': 0, 'rejected': 0, 'all': 0};
    }
  }

  static Stream<Map<String, int>> getAllStatusCountsStream() {
    return _db.collection('users').snapshots().map((snapshot) {
      int pending = 0;
      int verified = 0;
      int rejected = 0;
      for (var doc in snapshot.docs) {
        final status = (doc.data()['status'] ?? '').toString().toLowerCase();
        if (status == 'pending') {
          pending++;
        } else if (status == 'verified') {
          verified++;
        } else if (status == 'rejected') {
          rejected++;
        }
      }
      return {
        'pending': pending,
        'verified': verified,
        'rejected': rejected,
        'all': snapshot.docs.length,
      };
    });
  }

  static Future<void> toggleMessageAccess(
    String uid,
    bool canSendMessages,
  ) async {
    await _db.collection('users').doc(uid).update({
      'can_send_messages': canSendMessages,
    });
  }

  static Future<int> getPendingRequestsCount() async {
    try {
      final snapshot = await _db
          .collection('users')
          .where('status', isEqualTo: 'pending')
          .count()
          .get();
      return snapshot.count ?? 0;
    } catch (e) {
      return 0;
    }
  }

  static Stream<int> getPendingRequestsCountStream() {
    return _db
        .collection('users')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  static Stream<List<Map<String, dynamic>>> getRequestsStream(
    String status, {
    int limit = 20,
  }) {
    Query query = _db.collection('users');
    if (status != 'all') {
      query = query.where('status', isEqualTo: status.toLowerCase());
    }
    return query
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) => {
                  ...(doc.data() as Map<String, dynamic>),
                  'id': doc.id,
                },
              )
              .toList(),
        );
  }

  static Future<Map<String, dynamic>> getRequestsByStatus(
    String status,
    int page,
  ) async {
    Query query = _db.collection('users');
    if (status != 'all') {
      query = query.where('status', isEqualTo: status);
    }

    final countSnapshot = await query.count().get();
    final totalCount = countSnapshot.count ?? 0;

    final snapshot = await query
        .orderBy('created_at', descending: true)
        .limit(20)
        .get();

    return {
      'requests': snapshot.docs
          .map((doc) => {...(doc.data() as Map<String, dynamic>), 'id': doc.id})
          .toList(),
      'total': totalCount,
      'hasMore': totalCount > 20,
    };
  }

  static Future<Map<String, dynamic>> getAllRequestsByPagination(
    int page,
  ) async {
    return getRequestsByStatus('all', page);
  }

  // ===========================================================================
  // DEVICE REJECTION (LOCAL COOLDOWN)
  // ===========================================================================

  static const String _rejectionKey = 'device_rejection_time';
  static const String _rejectionUserIdKey = 'device_rejection_user_id';

  static Future<void> saveDeviceRejection(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_rejectionKey, DateTime.now().toIso8601String());
    await prefs.setString(_rejectionUserIdKey, uid);
  }

  static Future<String?> getDeviceRejectionUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_rejectionUserIdKey);
  }

  static Future<DateTime?> getDeviceRejectionTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(_rejectionKey);
    if (timeStr == null) return null;
    return DateTime.tryParse(timeStr);
  }

  static Future<void> clearDeviceRejection() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_rejectionKey);
    await prefs.remove(_rejectionUserIdKey);
  }
}
