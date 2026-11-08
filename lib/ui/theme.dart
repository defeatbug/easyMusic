import 'package:flutter/material.dart';

/// The desktop app's light palette, taken from MyGo Music's paletteFor():
/// white content, #f4f4f6 sidebar, near-black text in the (60,60,67)
/// family, and a red accent (Oklch 0.6/0.21/24 ≈ #E2333C).
abstract final class Palette {
  static const bg = Color(0xFFFFFFFF);
  static const sidebar = Color(0xFFF4F4F6);
  static const text = Color(0xFF1D1D1F);
  static const muted = Color.fromRGBO(60, 60, 67, 0.62);
  static const faint = Color.fromRGBO(60, 60, 67, 0.32);
  static const hairline = Color.fromRGBO(0, 0, 0, 0.07);
  static const hover = Color.fromRGBO(0, 0, 0, 0.04);
  static const press = Color.fromRGBO(0, 0, 0, 0.08);
  static const accent = Color(0xFFE2333C);
  static const onAccent = Color(0xFFFFFFFF);
  static const cardShade = Color.fromRGBO(0, 0, 0, 0.16);
}

/// Sidebar width in the desktop layout; below a window width of 720 the
/// sidebar collapses to an icon rail (see shell.dart).
const double sidebarWidth = 232;

/// Below this window width the shell switches to the phone layout:
/// no sidebar at all, a mini player bar and a bottom tab bar instead
/// (see shell.dart). Between this and 720 the desktop frame keeps its
/// icon rail.
const double mobileBreakpoint = 600;

/// Height of the player bar along the foot of the content.
const double playerBarHeight = 84;

/// Horizontal page padding, as in the desktop app.
const double pagePad = 40;

ThemeData appTheme() {
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'NotoSansCJK',
    fontFamilyFallback: const [
      'Noto Sans CJK SC',
      'PingFang SC',
      'Microsoft YaHei',
      'sans-serif',
    ],
    scaffoldBackgroundColor: Palette.bg,
    colorScheme: const ColorScheme.light(
      primary: Palette.accent,
      onPrimary: Palette.onAccent,
      surface: Palette.bg,
      onSurface: Palette.text,
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: Palette.text),
      bodySmall: TextStyle(color: Palette.muted),
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Palette.hover,
    hoverColor: Palette.hover,
    dividerColor: Palette.hairline,
    iconTheme: const IconThemeData(color: Palette.text),
  );
}
