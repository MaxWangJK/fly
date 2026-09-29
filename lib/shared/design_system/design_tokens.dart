import 'package:flutter/material.dart';

abstract final class FlyColors {
  static const canvasLight = Color(0xFFF4E9DC);
  static const surfaceLight = Color(0xFFFFFCF8);
  static const primaryRailLight = Color(0xFFDDCBBB);
  static const sidebarLight = Color(0xFFF0E3D6);
  static const hoverLight = Color(0xFFF8F0E8);
  static const selectedLight = Color(0xFFE5EEDC);
  static const completedLight = Color(0xFFF5F0E9);
  static const inkLight = Color(0xFF191827);
  static const inkMutedLight = Color(0xFF77736F);
  static const borderLight = Color(0xFFE4DAD0);

  static const canvasDark = Color(0xFF17181A);
  static const surfaceDark = Color(0xFF202124);
  static const primaryRailDark = Color(0xFF18191B);
  static const sidebarDark = Color(0xFF1C1D20);
  static const hoverDark = Color(0xFF282A2E);
  static const selectedDark = Color(0xFF303238);
  static const completedDark = Color(0xFF242528);
  static const inkDark = Color(0xFFF1F2F4);
  static const inkMutedDark = Color(0xFFA5A8AE);
  static const borderDark = Color(0xFF34363B);

  static const accent = Color(0xFF7D9F62);
  static const accentSoft = Color(0xFFEDF3E7);
  static const success = Color(0xFF6D9A68);
  static const warning = Color(0xFFD98C4F);
  static const danger = Color(0xFFC86C70);

  static const importantUrgent = Color(0xFFC86168);
  static const importantCalm = Color(0xFFC6903E);
  static const urgentLight = Color(0xFF5E7BB8);
  static const someday = Color(0xFF5F8D78);

  static const calendarBlue = Color(0xFFE8EFF2);
  static const calendarGreen = Color(0xFFE5F0DF);
  static const calendarPink = Color(0xFFF6E3E1);
  static const calendarYellow = Color(0xFFF7E5CD);
  static const calendarPurple = Color(0xFFECE7F5);
}

abstract final class FlySpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

abstract final class FlyRadius {
  static const double xs = 6;
  static const double sm = 9;
  static const double md = 12;
  static const double lg = 16;
}

abstract final class FlyElevation {
  static const double popup = 8;
  static const double dialog = 12;
}

abstract final class FlyType {
  static const double pageTitle = 22;
  static const double section = 15;
  static const double task = 14;
  static const double body = 13;
  static const double meta = 12;
}

abstract final class FlyMetrics {
  static const double primaryRailWidth = 52;
  static const double taskSidebarWidth = 236;
  static const double taskListWidth = 488;
  static const double detailMinWidth = 420;
  static const double detailSideWidth = 420;
  static const double taskRowHeight = 44;
  static const double compactTaskRowHeight = 25;
  static const double iconSm = 16;
  static const double iconMd = 19;
  static const double iconLg = 22;
}

abstract final class FlyBreakpoints {
  static const double medium = 760;
  static const double expanded = 1100;
}

abstract final class FlyMotion {
  static const Duration fast = Duration(milliseconds: 100);
  static const Duration standard = Duration(milliseconds: 180);
  static const Duration deliberate = Duration(milliseconds: 260);
  static const Duration autoSave = Duration(milliseconds: 450);
}
