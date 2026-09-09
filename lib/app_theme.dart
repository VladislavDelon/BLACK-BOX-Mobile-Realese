import 'package:flutter/material.dart';

class AppTheme {
  static const bg = Color(0xFF0F0F0F);
  static const card = Color(0xFF1A1A1A);
  static const hover = Color(0xFF2A2A2A);
  static const accent = Color(0xFF2ECC71);
  static const accent2 = Color(0xFF3498DB);
  static const text = Color(0xFFE0E0E0);
  static const muted = Color(0xFF8E8E8E);
  static const down = Color(0xFFE74C3C);
  static const up = Color(0xFF2ECC71);
  static const lock = Color(0xFF555555);

  static const double cornerRadius = 12.0;
  static const double buttonHeight = 52.0;

  static ThemeData dark() => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
          primary: accent,
          surface: card,
        ),
        cardColor: card,
        appBarTheme: const AppBarTheme(
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
            borderSide: const BorderSide(color: muted),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: muted),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: accent),
          ),
          labelStyle: const TextStyle(color: muted),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.black,
            minimumSize: const Size(double.infinity, buttonHeight),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(cornerRadius),
            ),
          ),
        ),
      );

  static TextStyle header() => const TextStyle(
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
