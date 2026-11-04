import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// PhamiJam's family look: warm charcoal surfaces, coral accent, PhamiJam gold for goals,
/// green/red for results.
class AppColors {
  static const background = Color(0xFF1C1B1A);
  static const surface = Color(0xFF2A2724);
  static const surfaceHigh = Color(0xFF35312C);
  static const surfaceLow = Color(0xFF201E1B);
  static const border = Color(0x14FFFFFF);
  static const text = Color(0xFFFFFFFF);
  static const textDim = Color(0xFFCBBFA8);
  static const textFaint = Color(0xFF8C8273);
  static const accent = Color(0xFFE0604E);
  static const goal = Color(0xFFDBA43A);
  static const goalSoft = Color(0xFFE9C77E);
  static const gain = Color(0xFF5BC98D);
  static const loss = Color(0xFFEF5B5B);
  static const live = Color(0xFF5BC98D);

  static Color delta(num value) => value > 0 ? gain : value < 0 ? loss : textDim;
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
