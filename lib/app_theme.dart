import 'package:flutter/material.dart';
import 'core/core_call.dart';

class AppTheme {
  static bool isLight = false;
  static final ValueNotifier<bool> themeNotifier = ValueNotifier(false);

  static Color get bg => isLight ? const Color(0xFFF2F2F2) : const Color(0xFF0F0F0F);
  static Color get card => isLight ? const Color(0xFFFFFFFF) : const Color(0xFF1A1A1A);
  static Color get hover => isLight ? const Color(0xFFE0E0E0) : const Color(0xFF2A2A2A);
  static Color get accent => isLight ? const Color(0xFF1E9E50) : const Color(0xFF2ECC71);
  static Color get accent2 => isLight ? const Color(0xFF2471A3) : const Color(0xFF3498DB);
  static Color get text => isLight ? const Color(0xFF1A1A1A) : const Color(0xFFE0E0E0);
  static Color get muted => isLight ? const Color(0xFF666666) : const Color(0xFF8E8E8E);
  static Color get down => const Color(0xFFE74C3C);
  static Color get up => isLight ? const Color(0xFF1E9E50) : const Color(0xFF2ECC71);
  static Color get lock => isLight ? const Color(0xFFBBBBBB) : const Color(0xFF555555);

  static const double cornerRadius = 12.0;
  static const double buttonHeight = 52.0;

  /// Применяет сохранённую тему без записи в настройки.
  static void applySaved(String? value) {
    isLight = value == 'light';
    themeNotifier.value = isLight;
  }

  /// Переключает тему и сохраняет выбор.
  static Future<void> setLight(bool v) async {
    isLight = v;
    themeNotifier.value = v;
    try {
      await coreCall('set_setting', {'key': 'theme', 'value': v ? 'light' : 'dark'});
    } catch (_) {}
  }

  static ThemeData theme() => isLight ? light() : dark();

  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData light() => _base(Brightness.light);

  static ThemeData _base(Brightness brightness) => ThemeData(
        brightness: brightness,
        scaffoldBackgroundColor: bg,
        colorScheme: brightness == Brightness.dark
            ? ColorScheme.dark(primary: accent, surface: card)
            : ColorScheme.light(primary: accent, surface: card),
        cardColor: card,
        appBarTheme: AppBarTheme(
          backgroundColor: bg,
          foregroundColor: text,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: text,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: muted),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: muted),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: accent),
          ),
          labelStyle: TextStyle(color: muted),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: isLight ? Colors.white : Colors.black,
            minimumSize: const Size(double.infinity, buttonHeight),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(cornerRadius),
            ),
          ),
        ),
      );

  static TextStyle header() => TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: text,
      );

  static TextStyle title({Color? color}) => TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: color ?? text,
      );

  static TextStyle body({Color? color}) => TextStyle(
        fontSize: 16,
        color: color ?? text,
      );

  static TextStyle small({Color? color}) => TextStyle(
        fontSize: 14,
        color: color ?? muted,
      );
}
