import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Dark graphite surfaces, one coral accent, magenta for goals, green/red for results.
class AppColors {
  static const background = Color(0xFF0C0C0E);
  static const cardTop = Color(0xFF1F1F22);
  static const cardBottom = Color(0xFF141416);
  static const surface = Color(0xFF18181B);
  static const surfaceHigh = Color(0xFF26262A);
  static const border = Color(0x12FFFFFF);
  static const text = Color(0xFFF4F4F5);
  static const textDim = Color(0xFF8E8E96);
  static const textFaint = Color(0xFF5E5E66);
  static const accent = Color(0xFFE5533D);
  static const goal = Color(0xFFCF4DF0);
  static const goalSoft = Color(0xFFB98CF5);
  static const gain = Color(0xFF4CC38A);
  static const loss = Color(0xFFF25555);
  static const live = Color(0xFF4CC38A);

  static Color delta(num value) => value > 0 ? gain : value < 0 ? loss : textDim;

  static const cardGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [cardTop, cardBottom],
  );
}

/// Space Grotesk throughout: spaced-out capitals for labels, bold capitals for headlines.
class AppText {
  /// Card and section labels: `TODAY · 6 GAMES`. Callers pass the text upper-cased.
  static TextStyle label({Color color = AppColors.textDim, double size = 11}) => TextStyle(
        fontFamily: 'SpaceGrotesk',
        fontSize: size,
        fontWeight: FontWeight.w500,
        letterSpacing: size * 0.16,
        color: color,
      );

  /// Numbers that should line up: `13,460 / 16,000`, countdowns.
  static TextStyle mono({Color color = AppColors.textDim, double size = 13}) => TextStyle(
        fontFamily: 'SpaceGrotesk',
        fontSize: size,
        color: color,
        letterSpacing: 0.4,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Headline numbers and names: `DIAMOND III`, `+359`.
  static TextStyle display(double size, {Color color = AppColors.text, FontWeight weight = FontWeight.w700}) => TextStyle(
        fontFamily: 'SpaceGrotesk',
        fontSize: size,
        fontWeight: weight == FontWeight.w800 || weight == FontWeight.w900 ? FontWeight.w700 : weight,
        color: color,
        height: 1.1,
        letterSpacing: size * 0.02,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: 'SpaceGrotesk',
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
      primary: AppColors.accent,
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
    dialogTheme: const DialogThemeData(backgroundColor: AppColors.surface),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      labelStyle: const TextStyle(color: AppColors.textDim),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// `+2,700` / `-35`.
String signed(num value) => '${value > 0 ? '+' : ''}${NumberFormat.decimalPattern().format(value)}';
