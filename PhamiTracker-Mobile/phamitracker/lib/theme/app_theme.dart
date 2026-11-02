import 'package:flutter/material.dart';

/// Clean dark base with two accents: orange (Apex) and purple (VALORANT).
class AppColors {
  static const background = Color(0xFF0B0B11);
  static const surface = Color(0xFF15151E);
  static const surfaceHigh = Color(0xFF1E1E29);
  static const border = Color(0x14FFFFFF);
  static const text = Color(0xFFF2F2F7);
  static const textDim = Color(0xFF9A9AAE);
  static const gain = Color(0xFF6CCF9C);
  static const loss = Color(0xFFEE7C88);
  static const live = Color(0xFF6CCF9C);
  static const orange = Color(0xFFF08C45);
  static const purple = Color(0xFF8B78F2);

  static Color delta(num value) => value > 0 ? gain : value < 0 ? loss : textDim;
}

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF8B78F2),
      brightness: Brightness.dark,
      surface: AppColors.surface,
    ),
    scaffoldBackgroundColor: AppColors.background,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      labelStyle: const TextStyle(color: AppColors.textDim),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

String signed(num value) => value > 0 ? '+$value' : '$value';
