import 'package:flutter/material.dart';

import 'design_tokens.dart';
import 'fly_color_scheme.dart';

abstract final class FlyTheme {
  static ThemeData light([FlyPaletteId palette = FlyPaletteId.flyDefault]) =>
      _build(Brightness.light, palette);
  static ThemeData dark([FlyPaletteId palette = FlyPaletteId.flyDefault]) =>
      _build(Brightness.dark, palette);

  static ThemeData _build(Brightness brightness, FlyPaletteId palette) {
    final colors = FlyColorScheme.resolve(palette, brightness);
    final surface = colors.surface;
    final canvas = colors.canvas;
    final ink = colors.textPrimary;
    final muted = colors.textSecondary;
    final border = colors.divider;
    final hover = colors.hover;

    final scheme =
        ColorScheme.fromSeed(
          seedColor: colors.accent,
          brightness: brightness,
          surface: surface,
          error: colors.danger,
        ).copyWith(
          primary: colors.accent,
          surface: colors.surface,
          surfaceContainerLowest: colors.surface,
          surfaceContainerLow: colors.surfaceMuted,
          surfaceContainer: colors.surfaceMuted,
          surfaceContainerHigh: colors.hover,
          surfaceContainerHighest: colors.selected,
          onSurface: colors.textPrimary,
          onSurfaceVariant: colors.textSecondary,
          outline: colors.divider,
          outlineVariant: colors.divider,
        );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      fontFamily: 'Microsoft YaHei UI',
      fontFamilyFallback: const ['Segoe UI', 'Microsoft YaHei', 'sans-serif'],
      visualDensity: VisualDensity.compact,
      splashFactory: InkRipple.splashFactory,
      extensions: [colors],
    );

    return base.copyWith(
      canvasColor: canvas,
      dividerColor: border,
      hoverColor: hover,
      focusColor: colors.accent.withValues(alpha: 0.10),
      highlightColor: Colors.transparent,
      textTheme: base.textTheme.copyWith(
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          color: ink,
          fontSize: FlyType.pageTitle,
          height: 1.25,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          color: ink,
          fontSize: 18,
          height: 1.3,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          color: ink,
          fontSize: FlyType.section,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          color: ink,
          fontSize: FlyType.task,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          color: ink,
          fontSize: FlyType.body,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          color: muted,
          fontSize: FlyType.meta,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          color: ink,
          fontSize: FlyType.body,
          fontWeight: FontWeight.w600,
        ),
        labelMedium: base.textTheme.labelMedium?.copyWith(
          color: muted,
          fontSize: FlyType.meta,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: surface,
        hintStyle: TextStyle(color: muted, fontSize: FlyType.body),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FlyRadius.sm),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FlyRadius.sm),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FlyRadius.sm),
          borderSide: BorderSide(color: colors.accent, width: 1.3),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: FlySpacing.sm,
          vertical: 10,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlyRadius.xs),
        ),
        side: BorderSide(color: muted, width: 1.2),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlyRadius.md),
          side: BorderSide(color: border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FlyRadius.sm),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FlyRadius.sm),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: muted, size: FlyMetrics.iconMd),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(32, 32),
          padding: const EdgeInsets.all(6),
          foregroundColor: muted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FlyRadius.sm),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: FlyElevation.dialog,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlyRadius.lg),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        elevation: FlyElevation.popup,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlyRadius.md),
          side: BorderSide(color: border),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(5),
        radius: const Radius.circular(3),
        thumbVisibility: const WidgetStatePropertyAll(false),
        interactive: true,
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => muted.withValues(
            alpha: states.contains(WidgetState.hovered) ? 0.55 : 0.24,
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(FlyRadius.xs),
        ),
        textStyle: TextStyle(color: surface, fontSize: FlyType.meta),
      ),
    );
  }
}
