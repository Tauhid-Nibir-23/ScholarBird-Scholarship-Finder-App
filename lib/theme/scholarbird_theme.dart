import 'package:flutter/material.dart';

/// Shared visual tokens for every ScholarBird screen.
abstract final class ScholarBirdColors {
  static const primary = Color(0xFF5B7AE8);
  static const primaryDark = Color(0xFF3D5AC1);
  static const background = Color(0xFFF5F7FB);
  static const surface = Colors.white;
  static const ink = Color(0xFF1A1A2E);
  static const body = Color(0xFF6B7A95);
  static const muted = Color(0xFF9CA3AF);
  static const border = Color(0xFFE5E7EB);
}

abstract final class ScholarBirdSpacing {
  static const xSmall = 8.0;
  static const small = 12.0;
  static const medium = 16.0;
  static const large = 20.0;
  static const xLarge = 24.0;
}

abstract final class ScholarBirdTheme {
  static const _radius = 12.0;

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: ScholarBirdColors.primary,
      brightness: Brightness.light,
      primary: ScholarBirdColors.primary,
      surface: ScholarBirdColors.surface,
      error: const Color(0xFFDC2626),
    );
    final textTheme = Typography.material2021()
        .black
        .apply(
          fontFamily: 'Roboto',
          bodyColor: ScholarBirdColors.ink,
          displayColor: ScholarBirdColors.ink,
        )
        .copyWith(
          headlineSmall:
              const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          titleLarge:
              const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          titleMedium:
              const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          titleSmall:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          bodyLarge: const TextStyle(fontSize: 16, height: 1.5),
          bodyMedium: const TextStyle(fontSize: 14, height: 1.45),
          bodySmall: const TextStyle(fontSize: 12, height: 1.4),
          labelLarge:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          labelMedium:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        );

    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_radius),
      borderSide: const BorderSide(color: ScholarBirdColors.border),
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: ScholarBirdColors.background,
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: ScholarBirdColors.surface,
        foregroundColor: ScholarBirdColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 64,
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          color: ScholarBirdColors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: ScholarBirdColors.ink),
      ),
      cardTheme: CardThemeData(
        color: ScholarBirdColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: ScholarBirdColors.border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 48),
          backgroundColor: ScholarBirdColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              ScholarBirdColors.primary.withValues(alpha: .45),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: ScholarBirdSpacing.medium,
            vertical: ScholarBirdSpacing.small,
          ),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radius)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          foregroundColor: ScholarBirdColors.primary,
          padding: const EdgeInsets.symmetric(
            horizontal: ScholarBirdSpacing.medium,
            vertical: ScholarBirdSpacing.small,
          ),
          textStyle: textTheme.labelLarge,
          side: const BorderSide(color: ScholarBirdColors.primary),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radius)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ScholarBirdColors.primary,
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radius)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ScholarBirdColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ScholarBirdSpacing.medium,
          vertical: ScholarBirdSpacing.medium,
        ),
        labelStyle:
            textTheme.bodyMedium?.copyWith(color: ScholarBirdColors.body),
        hintStyle:
            textTheme.bodyMedium?.copyWith(color: ScholarBirdColors.muted),
        enabledBorder: outline,
        focusedBorder: outline.copyWith(
          borderSide:
              const BorderSide(color: ScholarBirdColors.primary, width: 2),
        ),
        errorBorder: outline.copyWith(
          borderSide: const BorderSide(color: Color(0xFFDC2626)),
        ),
        focusedErrorBorder: outline.copyWith(
          borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: ScholarBirdColors.primary,
      ),
    );
  }
}
