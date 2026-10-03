import 'package:flutter/material.dart';

// Minimalist palette derived from the logo: mostly neutral surfaces, navy/blue as the only
// brand accent, and red reserved for errors, removals and active locks.
const _seed = Color(0xFF2E5BA8);

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: b).copyWith(
    primary: dark ? const Color(0xFF9DB6E0) : const Color(0xFF1E4A99),
    onPrimary: dark ? const Color(0xFF0B1B3A) : Colors.white,
    primaryContainer: dark ? const Color(0xFF1E2A44) : const Color(0xFFE3EAF6),
    onPrimaryContainer: dark ? const Color(0xFFDCE6F7) : const Color(0xFF0B1B3A),
    surface: dark ? const Color(0xFF14171C) : Colors.white,
    outlineVariant: dark ? const Color(0xFF2A2F38) : const Color(0xFFD9DEE7),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    scaffoldBackgroundColor: dark ? const Color(0xFF0F1115) : const Color(0xFFF6F7F9),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      color: dark ? const Color(0xFF171A20) : Colors.white,
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
  static const added = Color(0xFF3FA37A);
  static const removed = Color(0xFFD64045);
  static const modified = Color(0xFFD9971A);
  static const locked = Color(0xFFD64045);
  static const released = Color(0xFF3FA37A);
  static const unknown = Color(0xFFD9971A);

  // Chart series: blues, slates and teals; no red so that it keeps its "danger" meaning.
  static const series = <Color>[
    Color(0xFF4F7CC4),
    Color(0xFF2F9E8F),
    Color(0xFF8A97AD),
    Color(0xFFD9971A),
    Color(0xFF7A6BBF),
    Color(0xFF6FA8DC),
    Color(0xFF3FA37A),
    Color(0xFF5B6B86),
  ];

  static Color of(int i) => series[i % series.length];
}
