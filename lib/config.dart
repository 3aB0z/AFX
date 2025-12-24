import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class Config {
  // ==================== ENVIRONMENT DETECTION ====================
  /// Current environment (development, staging, production)
  static String get environment => dotenv.env['ENVIRONMENT'] ?? 'development';

  /// Is running in production
  static bool get isProduction => environment == 'production';

  /// Is running in debug/development mode
  static bool get isDevelopment => kDebugMode;

  // ==================== SUPABASE CREDENTIALS (from .env) ====================
  /// Supabase project URL
  static String get supabaseUrl =>
      dotenv.env['SUPABASE_URL'] ?? 'https://civbkywputkymyrhhliv.supabase.co';

  /// Supabase anonymous key (public, for client-side operations)
  static String get supabaseAnonKey =>
      dotenv.env['SUPABASE_ANON_KEY'] ??
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNpdmJreXdwdXRreW15cmhobGl2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUzNzQ5NjYsImV4cCI6MjA4MDk1MDk2Nn0.l5LnVkboRX4yYlQHUeZhabo_VY6d8525lLjEpek5h1I';

  /// Supabase service role key (secret, for server-side/admin operations)
  /// ⚠️ SECURITY: Keep this key secure!
  /// This key bypasses Row Level Security and should only be used for legitimate admin operations.
  /// Available in both development and production for authorized admin users.
  static String get supabaseServiceRoleKey =>
      dotenv.env['SUPABASE_SERVICE_ROLE_KEY'] ?? '';

  /// Base URL for the backend API.
  ///
  /// - On Android emulators use `http://10.0.2.2:5000` (alias to host machine).
  /// - On iOS simulators use `http://localhost:5000` (simulator maps to host).
  /// - For web use `http://localhost:5000`
  /// - For real devices, we try multiple IP addresses for different networks
  static String get baseUrl {
    // For web platform
    if (kIsWeb) {
      return 'http://localhost:5000';
    }

    // For mobile platforms
    if (Platform.isIOS) {
      return 'http://localhost:5000';
    } else if (Platform.isAndroid) {
      // Use specific IP for Android devices
      // For home network
      // return 'http://192.168.1.8:5000';
      // For work network
      return 'http://192.168.0.68:5000';
    }

    // Default fallback
    return 'http://localhost:5000';
  }

  // ==================== PRIMARY COLOR VARIATIONS ====================
  /// Primary color (green) used throughout the app
  static const Color primaryColor = Color.fromARGB(
    255,
    76,
    175,
    80,
  ); // Material Green 500

  /// Very dark green (darkest variation of primary)
  static const Color primaryDarkest = Color.fromARGB(
    255,
    27,
    94,
    32,
  ); // Material Green 900

  /// Dark green
  static const Color primaryDark = Color.fromARGB(
    255,
    56,
    142,
    60,
  ); // Material Green 700

  /// Medium green
  static const Color primaryMedium = Color.fromARGB(
    255,
    76,
    175,
    80,
  ); // Material Green 500

  /// Light green
  static const Color primaryLight = Color.fromARGB(
    255,
    129,
    199,
    132,
  ); // Material Green 300

  /// Very light green (lightest variation)
  static const Color primaryLightest = Color.fromARGB(
    255,
    200,
    230,
    201,
  ); // Material Green 100

  // ==================== SECONDARY COLOR VARIATIONS ====================
  /// Secondary color - actual lightGreen from Flutter
  static const Color secondaryColor = Color.fromARGB(
    255,
    139,
    195,
    74,
  ); // Material LightGreen 500

  /// Darker variation of secondary
  static const Color secondaryDark = Color.fromARGB(
    255,
    104,
    159,
    56,
  ); // Material LightGreen 700

  /// Lighter variation of secondary (for gradient effects)
  static const Color secondaryLight = Color.fromARGB(
    255,
    175,
    221,
    105,
  ); // Material LightGreen 300

  /// Very light secondary
  static const Color secondaryLightest = Color.fromARGB(
    255,
    205,
    235,
    159,
  ); // Material LightGreen 100

  // ==================== PURPLE COLORS (FOR NON-ADMIN MESSAGES) ====================
  /// Light purple color used for non-admin messages
  static const Color lightPurpleColor = Color.fromARGB(255, 233, 230, 236);

  /// Very light purple color used for non-admin message gradients
  static const Color veryLightPurpleColor = Color.fromARGB(255, 247, 244, 250);

  /// Darker light purple
  static const Color purpleDark = Color.fromARGB(255, 215, 200, 220);

  /// Even darker purple
  static const Color purpleDarker = Color.fromARGB(255, 180, 155, 195);

  // ==================== TEXT COLORS ====================
  /// Primary text color (dark text for light backgrounds)
  static const Color textPrimary = Color.fromARGB(255, 44, 44, 44);

  /// Secondary text color (medium dark text)
  static const Color textSecondary = Color.fromARGB(255, 87, 87, 87);

  /// Tertiary text color (lighter text)
  static const Color textTertiary = Color.fromARGB(255, 138, 138, 138);

  /// Quaternary text color (even lighter text)
  static const Color textQuaternary = Color.fromARGB(255, 170, 170, 170);

  /// Hint text color (very light text)
  static const Color textHint = Color.fromARGB(255, 189, 189, 189);

  /// Light text color (for dark backgrounds)
  static const Color textLight = Colors.white;

  /// Text color for messages (white)
  static const Color textMessage = Color.fromARGB(255, 255, 255, 255);

  /// Text color for time stamps
  static const Color textTimestamp = Color.fromARGB(255, 245, 245, 245);

  /// Text color for admin names in messages
  static const Color textAdminName = primaryColor;

  // ==================== UTILITY COLORS ====================
  /// Error/Delete color (red)
  static final Color error = Colors.red[400]!;

  /// Success color (green - same as primary)
  static const Color success = primaryColor;

  /// Warning color (orange)
  static const Color warning = Colors.orange;

  /// Info color (blue)
  static const Color info = Colors.blue;

  /// Divider color (light gray)
  static const Color divider = Color.fromARGB(255, 229, 229, 229);

  /// Background color (very light)
  static const Color background = Colors.white;

  /// Shadow color (black with transparency)
  static const Color shadow = Color.fromARGB(19, 0, 0, 0);

  // ==================== MESSAGE COLORS ====================
  /// Admin/Current user message background (primary gradient start)
  static const Color messageBgAdminStart = primaryColor;

  /// Admin/Current user message background (secondary gradient end)
  static const Color messageBgAdminEnd = secondaryColor;

  /// Other user message background (light purple start)
  static const Color messageBgOtherStart = lightPurpleColor;

  /// Other user message background (very light purple end)
  static const Color messageBgOtherEnd = veryLightPurpleColor;

  // ==================== BORDER & SHADOW COLORS ====================
  /// Primary border color
  static const Color borderPrimary = primaryLight;

  /// Secondary border color
  static const Color borderSecondary = divider;

  /// Message border color with transparency
  static Color messageBorderAdmin(double alpha) =>
      messageBgAdminStart.withAlpha((alpha * 255).toInt());
  static Color messageBorderOther(double alpha) =>
      messageBgOtherStart.withAlpha((alpha * 255).toInt());
}
