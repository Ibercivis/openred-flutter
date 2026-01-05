import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLocale {
  static const _prefsKey = 'app_locale';

  /// `null` means "follow system".
  static final ValueNotifier<Locale?> locale = ValueNotifier<Locale?>(null);

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      locale.value = _parse(raw);
    } catch (_) {
      locale.value = null;
    }
  }

  static Future<void> set(Locale? value) async {
    locale.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setString(_prefsKey, value.languageCode);
      }
    } catch (_) {
      // ignore
    }
  }

  static Locale? _parse(String? raw) {
    final code = (raw ?? '').trim().toLowerCase();
    if (code.isEmpty) return null;
    if (code == 'en') return const Locale('en');
    if (code == 'es') return const Locale('es');
    return null;
  }
}
