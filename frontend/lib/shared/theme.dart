import 'package:flutter/material.dart';

const _seed = Color(0xFF5B4FE0);

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: b);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    scaffoldBackgroundColor: b == Brightness.dark ? const Color(0xFF111118) : const Color(0xFFF6F6FB),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      color: b == Brightness.dark ? const Color(0xFF1A1A24) : Colors.white,
    ),
    appBarTheme: const AppBarTheme(centerTitle: false, scrolledUnderElevation: 0),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide.none,
    ),
  );
}

/// Semantic colors (also readable in dark mode).
class Palette {
  static const added = Color(0xFF2EA043);
  static const removed = Color(0xFFE5484D);
  static const modified = Color(0xFFD9971A);
  static const locked = Color(0xFFE5484D);
  static const released = Color(0xFF2EA043);
  static const unknown = Color(0xFFD9971A);

  static const series = <Color>[
    Color(0xFF5B4FE0),
    Color(0xFF12A594),
    Color(0xFFE5484D),
    Color(0xFFD9971A),
    Color(0xFF3E63DD),
    Color(0xFFAB4ABA),
    Color(0xFF30A46C),
    Color(0xFFF76808),
  ];

  static Color of(int i) => series[i % series.length];
}
