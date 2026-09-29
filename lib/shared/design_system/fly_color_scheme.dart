import 'package:flutter/material.dart';

enum FlyPaletteId { flyDefault, graphite, warmSand, ocean, forest }

extension FlyPaletteIdX on FlyPaletteId {
  String get label => switch (this) {
    FlyPaletteId.flyDefault => 'Fly 默认',
    FlyPaletteId.graphite => '石墨',
    FlyPaletteId.warmSand => '暖沙',
    FlyPaletteId.ocean => '海洋',
    FlyPaletteId.forest => '森林',
  };

  static FlyPaletteId parse(String? value) => FlyPaletteId.values.firstWhere(
    (entry) => entry.name == value,
    orElse: () => FlyPaletteId.flyDefault,
  );
}

@immutable
class FlyColorScheme extends ThemeExtension<FlyColorScheme> {
  const FlyColorScheme({
    required this.primaryRail,
    required this.secondarySidebar,
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.selected,
    required this.hover,
    required this.accent,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.danger,
    required this.warning,
    required this.success,
  });

  final Color primaryRail;
  final Color secondarySidebar;
  final Color canvas;
  final Color surface;
  final Color surfaceMuted;
  final Color selected;
  final Color hover;
  final Color accent;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color danger;
  final Color warning;
  final Color success;

  static FlyColorScheme of(BuildContext context) =>
      Theme.of(context).extension<FlyColorScheme>()!;

  static FlyColorScheme resolve(FlyPaletteId id, Brightness brightness) {
    if (brightness == Brightness.dark) {
      final accent = switch (id) {
        FlyPaletteId.flyDefault => const Color(0xFF8CAD73),
        FlyPaletteId.graphite => const Color(0xFF9AA3AD),
        FlyPaletteId.warmSand => const Color(0xFFC59B65),
        FlyPaletteId.ocean => const Color(0xFF68A5B7),
        FlyPaletteId.forest => const Color(0xFF70A486),
      };
      return FlyColorScheme(
        primaryRail: const Color(0xFF18191B),
        secondarySidebar: Color.alphaBlend(
          accent.withValues(alpha: .055),
          const Color(0xFF1C1D20),
        ),
        canvas: Color.alphaBlend(
          accent.withValues(alpha: .025),
          const Color(0xFF17181A),
        ),
        surface: const Color(0xFF202124),
        surfaceMuted: const Color(0xFF242528),
        selected: Color.alphaBlend(
          accent.withValues(alpha: .17),
          const Color(0xFF292B2F),
        ),
        hover: const Color(0xFF282A2E),
        accent: accent,
        divider: const Color(0xFF34363B),
        textPrimary: const Color(0xFFF1F2F4),
        textSecondary: const Color(0xFFA5A8AE),
        danger: const Color(0xFFD4777B),
        warning: const Color(0xFFE09B61),
        success: const Color(0xFF79A975),
      );
    }
    return switch (id) {
      FlyPaletteId.flyDefault => const FlyColorScheme(
        primaryRail: Color(0xFFDDCBBB),
        secondarySidebar: Color(0xFFF0E3D6),
        canvas: Color(0xFFF4E9DC),
        surface: Color(0xFFFFFCF8),
        surfaceMuted: Color(0xFFF5F0E9),
        selected: Color(0xFFE5EEDC),
        hover: Color(0xFFF8F0E8),
        accent: Color(0xFF7D9F62),
        divider: Color(0xFFE4DAD0),
        textPrimary: Color(0xFF191827),
        textSecondary: Color(0xFF77736F),
        danger: Color(0xFFC86C70),
        warning: Color(0xFFD98C4F),
        success: Color(0xFF6D9A68),
      ),
      FlyPaletteId.graphite => const FlyColorScheme(
        primaryRail: Color(0xFFD5D8DC),
        secondarySidebar: Color(0xFFE9EBED),
        canvas: Color(0xFFF1F2F3),
        surface: Color(0xFFFCFCFC),
        surfaceMuted: Color(0xFFF0F1F2),
        selected: Color(0xFFDDE3E8),
        hover: Color(0xFFF0F2F4),
        accent: Color(0xFF596673),
        divider: Color(0xFFD9DDE1),
        textPrimary: Color(0xFF1B2025),
        textSecondary: Color(0xFF6F7881),
        danger: Color(0xFFB9686D),
        warning: Color(0xFFC6894F),
        success: Color(0xFF668E73),
      ),
      FlyPaletteId.warmSand => const FlyColorScheme(
        primaryRail: Color(0xFFDFC9AF),
        secondarySidebar: Color(0xFFF2E3D1),
        canvas: Color(0xFFF5EADD),
        surface: Color(0xFFFFFCF7),
        surfaceMuted: Color(0xFFF7EFE5),
        selected: Color(0xFFF1DFC5),
        hover: Color(0xFFFAF2E8),
        accent: Color(0xFFA77642),
        divider: Color(0xFFE6D6C4),
        textPrimary: Color(0xFF251D17),
        textSecondary: Color(0xFF7C7065),
        danger: Color(0xFFC06D66),
        warning: Color(0xFFC88A45),
        success: Color(0xFF748E61),
      ),
      FlyPaletteId.ocean => const FlyColorScheme(
        primaryRail: Color(0xFFC7DDE1),
        secondarySidebar: Color(0xFFE0EEF0),
        canvas: Color(0xFFEAF3F4),
        surface: Color(0xFFFBFEFE),
        surfaceMuted: Color(0xFFEDF5F6),
        selected: Color(0xFFD5E9ED),
        hover: Color(0xFFEAF4F6),
        accent: Color(0xFF397F91),
        divider: Color(0xFFD3E3E6),
        textPrimary: Color(0xFF162326),
        textSecondary: Color(0xFF67797D),
        danger: Color(0xFFC1696F),
        warning: Color(0xFFD08A4C),
        success: Color(0xFF5D917E),
      ),
      FlyPaletteId.forest => const FlyColorScheme(
        primaryRail: Color(0xFFC9D8CB),
        secondarySidebar: Color(0xFFE1EBE2),
        canvas: Color(0xFFEAF1EA),
        surface: Color(0xFFFCFEFB),
        surfaceMuted: Color(0xFFEEF4ED),
        selected: Color(0xFFD8E8D8),
        hover: Color(0xFFEDF4EC),
        accent: Color(0xFF4E7D60),
        divider: Color(0xFFD5E0D4),
        textPrimary: Color(0xFF18231B),
        textSecondary: Color(0xFF68766B),
        danger: Color(0xFFBB6B6B),
        warning: Color(0xFFCA8B4B),
        success: Color(0xFF568568),
      ),
    };
  }

  @override
  FlyColorScheme copyWith() => this;

  @override
  FlyColorScheme lerp(covariant FlyColorScheme? other, double t) {
    if (other == null) return this;
    Color blend(Color a, Color b) => Color.lerp(a, b, t)!;
    return FlyColorScheme(
      primaryRail: blend(primaryRail, other.primaryRail),
      secondarySidebar: blend(secondarySidebar, other.secondarySidebar),
      canvas: blend(canvas, other.canvas),
      surface: blend(surface, other.surface),
      surfaceMuted: blend(surfaceMuted, other.surfaceMuted),
      selected: blend(selected, other.selected),
      hover: blend(hover, other.hover),
      accent: blend(accent, other.accent),
      divider: blend(divider, other.divider),
      textPrimary: blend(textPrimary, other.textPrimary),
      textSecondary: blend(textSecondary, other.textSecondary),
      danger: blend(danger, other.danger),
      warning: blend(warning, other.warning),
      success: blend(success, other.success),
    );
  }
}

extension FlyThemeColors on BuildContext {
  FlyColorScheme get flyColors => FlyColorScheme.of(this);
}
