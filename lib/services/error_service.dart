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

    state.showSnackBar(
      SnackBar(
        content: SelectionArea(
          child: Row(
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
        ),
        backgroundColor: isError ? Colors.red.shade400 : Colors.blue.shade400,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(12),
        action: SnackBarAction(
          label: 'DISMISS',
          textColor: Colors.white,
          onPressed: () {
            state.hideCurrentSnackBar();
          },
        ),
      ),
      snackBarAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 300),
        reverseDuration: Duration(milliseconds: 200),
      ),
    );
  }

  /// Helper to handle Firebase errors specifically
  static void handleFirebaseError(dynamic e, {String context = 'Operation'}) {
    String message = 'An unexpected error occurred.';

    // Safely convert to string to check error code/message
    final errStr = e.toString().toLowerCase();

    if (errStr.contains('permission-denied') ||
        errStr.contains('permission_denied')) {
      message = 'Access Denied: You do not have permission for this action.';
    } else if (errStr.contains('unavailable')) {
      message = 'Network Unavailable: Please check your internet connection.';
    } else if (errStr.contains('not-found')) {
      message = 'Item not found.';
    } else {
      message = '$context failed: ${e.toString()}';
    }

    debugPrint('[ERROR] $context: $e');
    show(message);
  }
}
