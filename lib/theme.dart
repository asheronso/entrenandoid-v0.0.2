import 'package:flutter/material.dart';
import 'store.dart';
import 'widgets.dart';

class Palette {
  final String name;
  final Color seed;
  const Palette(this.name, this.seed);
}

const palettes = [
  Palette('Neón violeta', Color(0xFF7C4DFF)),
  Palette('Fuego', Color(0xFFFF5722)),
  Palette('Océano', Color(0xFF0288D1)),
  Palette('Bosque', Color(0xFF2E7D32)),
  Palette('Rosa', Color(0xFFE91E63)),
  Palette('Dorado', Color(0xFFFFB300)),
  Palette('Grafito', Color(0xFF607D8B)),
];

ThemeData buildTheme(AppStore s) {
  final p = palettes[s.palette.clamp(0, palettes.length - 1)];
  final b = s.dark ? Brightness.dark : Brightness.light;
  var cs = ColorScheme.fromSeed(seedColor: p.seed, brightness: b);
  final black = s.dark && s.amoled;
  if (black) cs = cs.copyWith(surface: Colors.black);
  Panel.radius = s.radius;
  final r = BorderRadius.circular(s.radius);
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: black ? Colors.black : cs.surface,
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: r))),
    inputDecorationTheme: InputDecorationTheme(border: OutlineInputBorder(borderRadius: r)),
    appBarTheme: AppBarTheme(backgroundColor: black ? Colors.black : cs.surface, scrolledUnderElevation: 0),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: black ? Colors.black : null),
  );
}
