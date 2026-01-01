import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService {
  static const String _themeKey = 'theme_mode';

  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier(
    ThemeMode.system,
  );

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString(_themeKey);

    if (savedTheme != null) {
      if (savedTheme == 'light') {
        themeMode.value = ThemeMode.light;
      } else if (savedTheme == 'dark') {
        themeMode.value = ThemeMode.dark;
      } else {
        themeMode.value = ThemeMode.system;
      }
    }
    debugPrint('[THEME_SERVICE] 🎨 Initialized with theme: ${themeMode.value}');
  }

  static Future<void> setTheme(ThemeMode mode) async {
    themeMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    String value = 'system';
    if (mode == ThemeMode.light) value = 'light';
    if (mode == ThemeMode.dark) value = 'dark';

    await prefs.setString(_themeKey, value);
    debugPrint('[THEME_SERVICE] 🎨 Theme updated to: $value');
  }

  static String get themeModeString {
    if (themeMode.value == ThemeMode.light) return 'Light';
    if (themeMode.value == ThemeMode.dark) return 'Dark';
    return 'System';
  }
}
