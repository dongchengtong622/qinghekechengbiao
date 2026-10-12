import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const seed = Color(0xFF2E7D66);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      surface: const Color(0xFFF7FAF8),
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      useMaterial3: true,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(overlayColor: Colors.transparent),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(overlayColor: Colors.transparent),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(overlayColor: Colors.transparent),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(overlayColor: Colors.transparent),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(overlayColor: Colors.transparent),
      ),
      switchTheme: const SwitchThemeData(
        overlayColor: WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: const CheckboxThemeData(
        overlayColor: WidgetStatePropertyAll(Colors.transparent),
      ),
      radioTheme: const RadioThemeData(
        overlayColor: WidgetStatePropertyAll(Colors.transparent),
      ),
      tabBarTheme: const TabBarThemeData(
        overlayColor: WidgetStatePropertyAll(Colors.transparent),
      ),
      chipTheme: const ChipThemeData(
        elevation: 0,
        pressElevation: 0,
        shadowColor: Colors.transparent,
        selectedShadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
    );
  }
}
