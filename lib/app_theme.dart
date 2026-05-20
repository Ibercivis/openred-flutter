import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light mode seed — vibrant red, the "Open-red" identity.
const Color _kSeedLight = Color(0xFFD50000);

/// Dark mode seed — deep blue, creates a clean monitoring-station palette
/// with dark slate surfaces and a bright electric-blue primary.
const Color _kSeedDark = Color(0xFF0D47A1);

class AppTheme {
  static const _prefsKey = 'app_theme_mode';

  static final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      mode.value = _parse(prefs.getString(_prefsKey));
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
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Theme factories
  // ---------------------------------------------------------------------------

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme.fromSeed(
      seedColor: isDark ? _kSeedDark : _kSeedLight,
      brightness: brightness,
    );

    final textTheme = GoogleFonts.interTextTheme().copyWith(
      // Display — big headings, never used directly but good to configure
      displayLarge:  GoogleFonts.inter(fontSize: 57, fontWeight: FontWeight.w300),
      displayMedium: GoogleFonts.inter(fontSize: 45, fontWeight: FontWeight.w300),
      displaySmall:  GoogleFonts.inter(fontSize: 36, fontWeight: FontWeight.w300),
      // Headline — page/section titles
      headlineLarge:  GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w400),
      headlineMedium: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w400),
      headlineSmall:  GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w400),
      // Title — card titles, list items
      titleLarge:  GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w500),
      titleMedium: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w500),
      titleSmall:  GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500),
      // Body — main readable text
      bodyLarge:   GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400),
      bodyMedium:  GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400),
      bodySmall:   GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400),
      // Label — captions, buttons, chips
      labelLarge:  GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
      labelMedium: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500),
      labelSmall:  GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w400),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,

      // ----- Scaffold -------------------------------------------------------
      scaffoldBackgroundColor: scheme.surface,

      // ----- Cards ----------------------------------------------------------
      // In dark mode: use surfaceContainerHigh so cards sit visibly above the
      // scaffold. Add a subtle outline border for extra definition.
      cardTheme: CardThemeData(
        elevation: isDark ? 0 : 1,
        margin: EdgeInsets.zero,
        color: isDark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isDark
              ? BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.45),
                  width: 1,
                )
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
      ),

      // ----- AppBar ---------------------------------------------------------
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),

      // ----- NavigationBar (M3) ---------------------------------------------
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: isDark
            ? scheme.surfaceContainer
            : scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(
              color: scheme.onPrimaryContainer,
              size: 22,
            );
          }
          return IconThemeData(
            color: scheme.onSurfaceVariant,
            size: 22,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            );
          }
          return TextStyle(
            fontSize: 11,
            color: scheme.onSurfaceVariant,
          );
        }),
      ),

      // ----- ListTile -------------------------------------------------------
      listTileTheme: ListTileThemeData(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        minLeadingWidth: 28,
        iconColor: scheme.onSurfaceVariant,
      ),

      // ----- Inputs ---------------------------------------------------------
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        filled: true,
        fillColor: isDark
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerLowest,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      // ----- Buttons --------------------------------------------------------
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),

      // ----- Divider --------------------------------------------------------
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
        thickness: 1,
        space: 1,
      ),

      // ----- Icon -----------------------------------------------------------
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant),

      // ----- Chips ----------------------------------------------------------
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Parsing helpers
  // ---------------------------------------------------------------------------

  static ThemeMode _parse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _encode(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
