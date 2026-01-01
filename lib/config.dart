import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class Config {
  // ==================== ENVIRONMENT DETECTION ====================
  static String get environment => dotenv.env['ENVIRONMENT'] ?? 'development';
  static bool get isProduction => environment == 'production';
  static bool get isDevelopment => kDebugMode;

  static String get baseUrl {
    if (kIsWeb) return 'http://localhost:5000';
    if (Platform.isIOS) return 'http://localhost:5000';
    if (Platform.isAndroid) return 'http://192.168.0.68:5000';
    return 'http://localhost:5000';
  }

  // ==================== BRAND COLORS ====================
  static const Color primaryColor = Color(0xFF17AF61); // Material Green 500
  static const Color secondaryColor = Color(0xFF08BE60);

  // ==================== LIGHT THEME COLORS ====================
  static const Color bgLight = Colors.white;
  static const Color textPrimaryLight = Color(0xFF2C2C2C);
  static const Color textSecondaryLight = Color(0xFF575757);
  static const Color textTertiaryLight = Color(0xFF8A8A8A);
  static const Color dividerLight = Color(0xFFE5E5E5);
  static const Color surfaceLight = Color(0xFFFAFAFA);

  // ==================== DARK THEME COLORS ====================
  static const Color bgDark = Color(0xFF121212);
  static const Color textPrimaryDark = Color(0xFFE1E1E1);
  static const Color textSecondaryDark = Color(0xFFB0B0B0);
  static const Color textTertiaryDark = Color(0xFF757575);
  static const Color dividerDark = Color(0xFF2C2C2C);
  static const Color surfaceDark = Color(0xFF1E1E1E);

  // ==================== MESSAGE COLORS ====================
  // Current user / Admin messages (Green Gradient)
  static const Color messageAdminStart = primaryColor;
  static const Color messageAdminEnd = secondaryColor;

  // Other user messages
  static const Color messageOtherStartLight = Color(0xFFE9E6EC);
  static const Color messageOtherEndLight = Color(0xFFF7F4FA);
  static const Color messageOtherStartDark = Color(0xFF2C2C2E);
  static const Color messageOtherEndDark = Color(0xFF3A3A3C);

  // ==================== THEME HELPERS ====================
  static bool isDarkMode(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  static Color getBackgroundColor(BuildContext context) {
    return isDarkMode(context) ? bgDark : bgLight;
  }

  static Color getSurfaceColor(BuildContext context) {
    return isDarkMode(context) ? surfaceDark : surfaceLight;
  }

  static Color getTextColor(BuildContext context, {int level = 1}) {
    if (isDarkMode(context)) {
      if (level == 2) return textSecondaryDark;
      if (level == 3) return textTertiaryDark;
      return textPrimaryDark;
    } else {
      if (level == 2) return textSecondaryLight;
      if (level == 3) return textTertiaryLight;
      return textPrimaryLight;
    }
  }

  static Color getShadowColor(BuildContext context) {
    return isDarkMode(context) ? Colors.transparent : const Color.fromARGB(50, 0, 0, 0);
  }

  static Color getDividerColor(BuildContext context) {
    return isDarkMode(context) ? dividerDark : dividerLight;
  }

  static List<Color> getOtherMessageGradient(BuildContext context) {
    return isDarkMode(context)
        ? [messageOtherStartDark, messageOtherEndDark]
        : [messageOtherStartLight, messageOtherEndLight];
  }

  // Legacy support for constants (mapping to light theme for now)
  static final Color error = Colors.red[400]!;
  static const Color success = primaryColor;
  static const Color warning = Colors.orange;
  static const Color info = Colors.blue;
  static const Color background = bgLight;
  static const Color textPrimary = textPrimaryLight;
  static const Color textSecondary = textSecondaryLight;
  static const Color textTertiary = textTertiaryLight;
  static const Color textQuaternary = Color(0xFFAAAAAA);
  static const Color textHint = Color(0xFFBDBDBD);
  static const Color textLight = Colors.white;
  static const Color textMessage = Colors.white;
  static const Color textTimestamp = Color(0xFFF5F5F5);
  static const Color textAdminName = primaryColor;
  static const Color divider = dividerLight;
  static const Color lightPurpleColor = messageOtherStartLight;
  static const Color veryLightPurpleColor = messageOtherEndLight;
  static const Color borderSecondary = dividerLight;
  static const Color primaryLight = Color(0xFF81C784);
  static const Color primaryLightest = Color(0xFFC8E6C9);
}
