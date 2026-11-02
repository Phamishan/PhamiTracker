import 'package:flutter/material.dart';

/// Dark, high-contrast base with neon accents; each game brings its own gradient on top.
class AppColors {
  static const background = Color(0xFF07070D);
  static const surface = Color(0xFF11111B);
  static const surfaceHigh = Color(0xFF1A1A28);
  static const border = Color(0x1FFFFFFF);
  static const text = Color(0xFFF5F5FA);
  static const textDim = Color(0xFF9B9BB4);
  static const gain = Color(0xFF2EE59D);
  static const loss = Color(0xFFFF4D6D);
  static const live = Color(0xFF3DFF8B);
  static const cyan = Color(0xFF26D9FF);
  static const violet = Color(0xFF8B5CFF);
  static const gold = Color(0xFFFFC93C);

  static Color delta(num value) => value > 0 ? gain : value < 0 ? loss : textDim;
}

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFFF4655),
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
