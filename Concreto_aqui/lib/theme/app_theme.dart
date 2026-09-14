import 'package:flutter/material.dart';

class AppColors {
  static const ink = Color(0xFF1E2A38);
  static const inkSoft = Color(0xFF48586E);
  static const line = Color(0xFFD7D8D0);
  static const green = Color(0xFF3F7D5C);
  static const greenSoft = Color(0xFFE1EEE6);
  static const red = Color(0xFFA8402F);
  static const redSoft = Color(0xFFF5E2DE);
  static const amber = Color(0xFFAD7A28);
  static const amberSoft = Color(0xFFF2E6CC);

  static const accentConstrutora = ink;
  static const accentObra = amber;
  static const accentLaboratorio = green;
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFFF6F6F3),
    colorSchemeSeed: AppColors.ink,
    appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(9))),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
  );
}
