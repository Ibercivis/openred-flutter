import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppTheme {
  static const _prefsKey = 'app_theme_mode';

  /// Defaults to [ThemeMode.system].
  static final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      mode.value = _parse(raw);
    } catch (_) {
      mode.value = ThemeMode.system;
    }
  }

  static Future<void> set(ThemeMode value) async {
    mode.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == ThemeMode.system) {
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setString(_prefsKey, _encode(value));
      }
    } catch (_) {
      // ignore
    }
  }

  static ThemeMode _parse(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    if (v == 'light') return ThemeMode.light;
    if (v == 'dark') return ThemeMode.dark;
    return ThemeMode.system;
  }

  static String _encode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
