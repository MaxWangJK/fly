import 'package:flutter/material.dart';

abstract final class FlyColors {
  static const canvasLight = Color(0xFFF3F6FA);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceMutedLight = Color(0xFFEAF0F6);
  static const inkLight = Color(0xFF172033);
  static const inkMutedLight = Color(0xFF667085);
  static const borderLight = Color(0xFFDCE3EC);

  static const canvasDark = Color(0xFF10141D);
  static const surfaceDark = Color(0xFF181E29);
  static const surfaceMutedDark = Color(0xFF202938);
  static const inkDark = Color(0xFFF1F4F8);
  static const inkMutedDark = Color(0xFF9DA9B9);
  static const borderDark = Color(0xFF2A3546);

  static const accent = Color(0xFF4267E8);
  static const accentSoft = Color(0xFFE5EBFF);
  static const success = Color(0xFF2C8B69);
  static const warning = Color(0xFFD68C2F);
  static const danger = Color(0xFFC94A57);

  static const importantUrgent = Color(0xFFD85C61);
  static const importantCalm = Color(0xFF5B6FC7);
  static const urgentLight = Color(0xFFD58B3D);
  static const someday = Color(0xFF5D8B79);
}

abstract final class FlySpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

abstract final class FlyRadius {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 14;
}

abstract final class FlyMetrics {
  static const double sidebarWidth = 232;
  static const double compactRailWidth = 72;
  static const double detailWidth = 372;
  static const double taskRowHeight = 52;
  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 24;
}

abstract final class FlyBreakpoints {
  static const double medium = 760;
  static const double expanded = 1180;
}

abstract final class FlyMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration deliberate = Duration(milliseconds: 280);
}
