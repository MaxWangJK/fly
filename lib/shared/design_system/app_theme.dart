import 'package:flutter/material.dart';

import 'design_tokens.dart';

abstract final class FlyTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: FlyColors.accent,
      brightness: brightness,
      surface: isDark ? FlyColors.surfaceDark : FlyColors.surfaceLight,
      error: FlyColors.danger,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? FlyColors.canvasDark : FlyColors.canvasLight,
      visualDensity: VisualDensity.compact,
    );

    final ink = isDark ? FlyColors.inkDark : FlyColors.inkLight;
    final muted = isDark ? FlyColors.inkMutedDark : FlyColors.inkMutedLight;
    final border = isDark ? FlyColors.borderDark : FlyColors.borderLight;

    return base.copyWith(
      dividerColor: border,
      textTheme: base.textTheme.copyWith(
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          color: ink,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          color: ink,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          color: ink,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(color: ink),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(color: ink),
        bodySmall: base.textTheme.bodySmall?.copyWith(color: muted),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          color: ink,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor:
            isDark ? FlyColors.surfaceMutedDark : FlyColors.surfaceMutedLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FlyRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FlyRadius.md),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FlyRadius.md),
          borderSide: const BorderSide(color: FlyColors.accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: FlySpacing.md,
          vertical: FlySpacing.sm,
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? FlyColors.surfaceDark : FlyColors.surfaceLight,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlyRadius.md),
          side: BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? FlyColors.surfaceDark : FlyColors.surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlyRadius.lg),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        decoration: BoxDecoration(
          color: isDark ? FlyColors.inkDark : FlyColors.inkLight,
          borderRadius: BorderRadius.circular(FlyRadius.sm),
        ),
      ),
    );
  }
}
