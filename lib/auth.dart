import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class Auth {
  static const _key = 'afx_login';
  static const _tokenKey = 'afx_token';

  /// Save login info as JSON string. Example: {"id":123,"role":"user","name":"Ali"}
  static Future<void> saveLogin(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data));

    // Save token if present (for admin users)
    if (data.containsKey('token') && data['token'] != null) {
      await prefs.setString(_tokenKey, data['token']);
    }
  }

  /// Returns decoded login map or null if not saved.
  static Future<Map<String, dynamic>?> getLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_key);
    if (s == null) return null;
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return m;
    } catch (_) {
      return null;
    }
  }

  /// Get stored JWT token for admin users
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<void> clearLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await prefs.remove(_tokenKey);
  }
}
