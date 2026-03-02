import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'error_service.dart';

/// SecurityService provides secure communication with Cloud Functions
/// implementing Zero-Trust architecture with encryption and RBAC.
class SecurityService {
  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  /// Cache for decrypted message content
  static final Map<String, String> _decryptionCache = {};

  /// Secure storage for encryption keys
  static const _storage = FlutterSecureStorage();
  static const _keyName = 'e2ee_master_key';
  static enc.Key? _cachedKey;
  static Completer<void>? _initCompleter;

  /// Notifies listeners when the encryption key is ready
  static final ValueNotifier<bool> isKeyReady = ValueNotifier(false);

  /// Internal helper to call functions with platform-aware logic
  /// (Uses HTTP fallback on Windows because cloud_functions plugin lacks native support)
  static Future<Map<String, dynamic>> _callFunction(
    String name,
    Map<String, dynamic> data,
  ) async {
    // If on Windows, use HTTP fallback
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return await _callFunctionViaHttp(name, data);
    }

    // Standard platform (Android, iOS, macOS, Web)
    final callable = _functions.httpsCallable(name);
    final result = await callable.call<Map<String, dynamic>>(data);
    return result.data;
  }

  /// Manual HTTP call for Firebase Callable Functions (Windows fallback)
  static Future<Map<String, dynamic>> _callFunctionViaHttp(
    String name,
    Map<String, dynamic> data,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'User must be authenticated',
      );
    }

    final idToken = await user.getIdToken();
    const projectId = 'afx-chat-app';
    const region = 'us-central1';

    // Note: This URL pattern works for both Gen 1 and Gen 2 Firebase Callable functions
    final url = 'https://$region-$projectId.cloudfunctions.net/$name';

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({'data': data}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(response.body);
        return Map<String, dynamic>.from(body['result'] ?? {});
      } else {
        debugPrint(
          '[SECURITY] HTTP Error ${response.statusCode}: ${response.body}',
        );
        throw FirebaseFunctionsException(
          code: 'internal',
          message: 'Cloud Function error: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[SECURITY] HTTP Request failed: $e');
      rethrow;
    }
  }

  // ============================================================================
  // CLIENT-SIDE ENCRYPTION (E2EE)
  // ============================================================================

  /// Initialize security by ensuring we have a local key
  /// In a production Telegram-like app, this key would be derived/exchanged
  static Future<void> initializeSecurity() async {
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }
    _initCompleter = Completer<void>();

    try {
      // MIGRATION: Only fetch key if missing. No longer deleting on every start.

      // Try to load cached key first
      String? keyHex = await _storage.read(key: _keyName);

      if (keyHex != null) {
        _cachedKey = enc.Key.fromBase16(keyHex);
        isKeyReady.value = true;
        debugPrint('[SECURITY] 🔐 E2EE Master Key loaded from secure storage');
      } else {
        debugPrint(
          '[SECURITY] ⚠️ No local key found. Fetching Shared Group Key from server...',
        );
        try {
          // Fetch Shared Group Key from Cloud Function
          final data = await _callFunction('secureGetGroupKey', {});

          if (data['success'] == true && data['groupKey'] != null) {
            keyHex = data['groupKey'] as String;

            final newKey = enc.Key.fromBase16(keyHex);
            await _storage.write(key: _keyName, value: keyHex);
            _cachedKey = newKey;

            // Clear cache when key changes or is first loaded to ensure fresh decryption
            _decryptionCache.clear();
            isKeyReady.value = true;

            debugPrint(
              '[SECURITY] 📥 Shared Group Key fetched and stored securely',
            );
          } else {
            throw Exception('Failed to fetch group key: invalid response');
          }
        } catch (e) {
          debugPrint('[SECURITY] ❌ Failed to fetch Group Key: $e');
          isKeyReady.value = false;
          ErrorService.show(
            'Failed to sync encryption keys. Chat functionality limited.',
            isError: true,
          );
        }
      }
      _initCompleter!.complete();
    } catch (e) {
      debugPrint('[SECURITY] ❌ Security initialization failed: $e');
      _initCompleter!.completeError(e);
      _initCompleter = null; // Reset to allow retry
    }
  }

  /// Wipe all security data from memory and local storage (Call on Logout)
  static Future<void> resetSecurity() async {
    try {
      // 1. Clear memory
      _cachedKey = null;
      _initCompleter = null;
      _decryptionCache.clear();
      isKeyReady.value = false;

      // 2. Clear secure storage
      await _storage.delete(key: _keyName);

      debugPrint('[SECURITY] 🧹 Security data wiped successfully');
    } catch (e) {
      debugPrint('[SECURITY] ❌ Failed to wipe security data: $e');
    }
  }

  /// Encrypt content locally using AES-256-CTR
  static Future<String> encryptLocal(String plaintext) async {
    if (_cachedKey == null) {
      await initializeSecurity();
      // Double check after attempts
      if (_cachedKey == null) {
        throw Exception(
          'Encryption Key Missing. Restarting the app usually fixes this.',
        );
      }
    }
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(
      enc.AES(_cachedKey!, mode: enc.AESMode.ctr, padding: null),
    );
    final encrypted = encrypter.encrypt(plaintext, iv: iv);

    // Format: IV:EncryptedData (Base64)
    return '${iv.base64}:${encrypted.base64}';
  }

  /// Decrypt content locally
  static String? decryptLocal(String ciphertext) {
    if (_cachedKey == null) {
      return null; // Key not ready
    }

    // Check if it's the new format (IV:EncryptedData)
    final parts = ciphertext.split(':');

    // Legacy support: old server-side encrypted messages are iv:tag:data (length 3)
    if (parts.length != 2) {
      debugPrint('[SECURITY] Unsupported or legacy message format');
      return '[Legacy Encrypted Message]';
    }

    try {
      final iv = enc.IV.fromBase64(parts[0]);
      final data = parts[1];

      final encrypter = enc.Encrypter(
        enc.AES(_cachedKey!, mode: enc.AESMode.ctr, padding: null),
      );
      return encrypter.decrypt64(data, iv: iv);
    } catch (e) {
      // Don't spam logs for old messages causing padding errors
      if (!e.toString().contains('pad block')) {
        debugPrint('[SECURITY] Local decryption failed: $e');
      }
      return '[Encrypted Message]';
    }
  }

  /// Send a message securely with Client-Side Encryption
  static Future<SecureMessageResult> sendSecureMessage({
    required String content,
    String? clientId,
  }) async {
    try {
      // 1. Encrypt LOCALLY (E2EE)
      final encryptedBlob = await encryptLocal(content);

      // 2. Hash LOCALLY for local integrity storage (per user request)
      final localHash = hashContent(content);
      if (clientId != null) {
        await _storage.write(key: 'hash_$clientId', value: localHash);
      }

      // 3. Send encrypted blob to server (Server never sees plaintext)
      final data = await _callFunction('secureSendMessage', {
        'content': encryptedBlob,
        'clientId': clientId,
      });

      return SecureMessageResult(
        success: data['success'] ?? false,
        messageId: data['messageId'] ?? '',
        encryptedContent: encryptedBlob,
        contentHash: '', // Server no longer needs to send this
        timestamp: data['timestamp'] ?? '',
      );
    } catch (e) {
      debugPrint('[SECURITY] Send message error: $e');
      return SecureMessageResult(
        success: false,
        messageId: '',
        encryptedContent: '',
        contentHash: '',
        timestamp: '',
        error: e.toString(),
      );
    }
  }

  /// Decrypt a message locally (used by UI for incoming messages)
  static Future<String> decryptMessage({
    required String encryptedContent,
    required String messageId,
  }) async {
    // Check cache first
    if (_decryptionCache.containsKey(messageId)) {
      return _decryptionCache[messageId]!;
    }

    // Attempt local decryption (E2EE)
    final decrypted = decryptLocal(encryptedContent);
    if (decrypted != null) {
      _decryptionCache[messageId] = decrypted;
      return decrypted;
    }

    return '[Unable to decrypt - Key Mismatch]';
  }

  /// Manually add decrypted content to cache (used for newly sent messages)
  static void addToDecryptionCache(String messageId, String content) {
    if (messageId.isNotEmpty) {
      _decryptionCache[messageId] = content;
    }
  }

  /// Synchronously retrieve content from cache
  static String? tryGetCachedDecryptedContent(String messageId) {
    return _decryptionCache[messageId];
  }

  // ============================================================================
  // ADMIN OPERATIONS
  // ============================================================================

  /// Admin: Update user verification status
  static Future<OperationResult> updateUserStatus({
    required String targetUserId,
    required String status,
  }) async {
    try {
      final data = await _callFunction('secureUpdateUserStatus', {
        'targetUserId': targetUserId,
        'status': status,
      });

      return OperationResult(
        success: data['success'] ?? false,
        message: data['message'] ?? '',
      );
    } catch (e) {
      debugPrint('[SECURITY] Update status error: $e');
      return OperationResult(
        success: false,
        message: ErrorService.getFriendlyMessage(e, context: 'Update Status'),
      );
    }
  }

  /// Admin: Toggle user's message sending permission
  static Future<OperationResult> toggleMessageAccess({
    required String targetUserId,
    required bool canSendMessages,
  }) async {
    try {
      final data = await _callFunction('secureToggleMessageAccess', {
        'targetUserId': targetUserId,
        'canSendMessages': canSendMessages,
      });

      return OperationResult(
        success: data['success'] ?? false,
        message: data['message'] ?? '',
      );
    } catch (e) {
      debugPrint('[SECURITY] Toggle access error: $e');
      return OperationResult(
        success: false,
        message: ErrorService.getFriendlyMessage(e, context: 'Toggle Access'),
      );
    }
  }

  // ============================================================================
  // USER OPERATIONS
  // ============================================================================

  /// Resubmit a rejected request
  static Future<OperationResult> resubmitRequest() async {
    try {
      final data = await _callFunction('secureResubmitRequest', {});

      return OperationResult(
        success: data['success'] ?? false,
        message: data['message'] ?? '',
      );
    } catch (e) {
      debugPrint('[SECURITY] Resubmit error: $e');
      return OperationResult(
        success: false,
        message: ErrorService.getFriendlyMessage(
          e,
          context: 'Resubmit Request',
        ),
      );
    }
  }

  // ============================================================================
  // SESSION & TOKEN MANAGEMENT
  // ============================================================================

  /// Force refresh the user's ID token to get updated Custom Claims
  static Future<void> refreshSession() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.getIdToken(true); // Force refresh
        debugPrint('[SECURITY] Session refreshed');
      }
    } catch (e) {
      debugPrint('[SECURITY] Session refresh error: $e');
    }
  }

  /// Get current user's Custom Claims
  static Future<Map<String, dynamic>?> getCurrentClaims() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final idTokenResult = await user.getIdTokenResult(true);
        return idTokenResult.claims;
      }
    } catch (e) {
      debugPrint('[SECURITY] Get claims error: $e');
    }
    return null;
  }

  // ============================================================================
  // LOCAL UTILITIES (for verification/hashing on client side)
  // ============================================================================

  /// Create SHA-256 hash of content (for integrity verification)
  static String hashContent(String content) {
    final bytes = utf8.encode(content);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Verify content against a hash
  static bool verifyContentHash(String content, String expectedHash) {
    final actualHash = hashContent(content);
    return actualHash == expectedHash;
  }
}

// ============================================================================
// RESULT CLASSES
// ============================================================================

class SecureMessageResult {
  final bool success;
  final String messageId;
  final String encryptedContent;
  final String contentHash;
  final String timestamp;
  final String? error;

  SecureMessageResult({
    required this.success,
    required this.messageId,
    required this.encryptedContent,
    required this.contentHash,
    required this.timestamp,
    this.error,
  });
}

class OperationResult {
  final bool success;
  final String message;

  OperationResult({required this.success, required this.message});
}
