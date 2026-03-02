import 'package:flutter/material.dart';

class ErrorService {
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Show a global error snackbar
  static void show(String message, {bool isError = true}) {
    final state = messengerKey.currentState;
    if (state == null) {
      debugPrint(
        '[ERROR_SERVICE] ⚠️ ScaffoldMessenger state is null. Message: $message',
      );
      return;
    }

    state.removeCurrentSnackBar();
    state.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.info_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade400 : Colors.blue.shade400,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'DISMISS',
          textColor: Colors.white,
          onPressed: () {
            state.removeCurrentSnackBar();
          },
        ),
      ),
    );

    // Fail-safe: Force hide after 5 seconds in case platform timer fails
    Future.delayed(const Duration(seconds: 5), () {
      messengerKey.currentState?.removeCurrentSnackBar();
    });
  }

  /// Helper to handle Firebase errors specifically
  static void handleFirebaseError(dynamic e, {String context = 'Operation'}) {
    final message = getFriendlyMessage(e, context: context);
    debugPrint('[ERROR_SERVICE] ❌ $context: $e');
    show(message);
  }

  /// Map technical error codes to user-friendly messages
  static String getFriendlyMessage(dynamic e, {String context = 'Operation'}) {
    String message = 'Something went wrong. Please try again.';

    // Extract code if it's a FirebaseException or similar
    String code = '';
    final eStr = e.toString();
    if (eStr.contains('] ')) {
      // Often looks like [firebase_auth/user-not-found] ...
      final match = RegExp(r'\[(.*?)\]').firstMatch(eStr);
      if (match != null) code = match.group(1) ?? '';
    }

    final errStr = eStr.toLowerCase();

    // 1. Specific Error Mappings
    if (code.contains('user-not-found') || errStr.contains('user-not-found')) {
      message = 'No account found for this email.';
    } else if (code.contains('wrong-password') ||
        errStr.contains('wrong-password')) {
      message = 'Incorrect password. Please try again.';
    } else if (code.contains('invalid-email') ||
        errStr.contains('invalid-email')) {
      message = 'The email address is not valid.';
    } else if (code.contains('email-already-in-use') ||
        errStr.contains('email-already-in-use')) {
      message = 'This email is already registered.';
    } else if (code.contains('weak-password') ||
        errStr.contains('weak-password')) {
      message = 'Password is too weak.';
    } else if (code.contains('too-many-requests') ||
        errStr.contains('too-many-requests')) {
      message = 'Too many attempts. Please wait a moment and try again.';
    } else if (errStr.contains('permission-denied') ||
        errStr.contains('permission_denied')) {
      message = 'Access Denied: You don\'t have permission for this.';
    } else if (errStr.contains('unavailable') ||
        errStr.contains('network-request-failed')) {
      message = 'Network error: Please check your internet connection.';
    } else if (errStr.contains('not-found')) {
      message = 'The requested item was not found.';
    } else if (errStr.contains('unauthenticated')) {
      message = 'Please log in to continue.';
    } else if (errStr.contains('deadline-exceeded')) {
      message = 'Request timed out. Please try again.';
    } else {
      // 2. Generic context-based fallbacks (No raw error strings!)
      if (context == 'Login') message = 'Login failed. Check your credentials.';
      if (context == 'Sign Up') message = 'Sign up failed. Please try again.';
      if (context == 'Send Message') message = 'Could not send message.';
      if (context == 'Load History') message = 'Failed to load chat history.';
      if (context == 'Upload') message = 'File upload failed.';
    }

    return message;
  }
}
