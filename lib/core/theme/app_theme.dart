import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_palette.dart';
import 'theme_controller.dart';

class AppColors {
  static AppPalette get _p => ThemeController.to.palette.value;

  static Color get bg => _p.bg;
  static Color get surface => _p.surface;
  static Color get surface2 => _p.surface2;
  static Color get border => _p.border;
  static Color get accent => _p.accent;
  static Color get accent2 => _p.accent2;
  static Color get accent3 => _p.accent3;
  static Color get yellow => _p.yellow;
  static Color get textPrimary => _p.textPrimary;
  static Color get textMuted => _p.textMuted;
  static Color get online => _p.online;
  static Color get error => _p.error;

  static LinearGradient get gradientPink => _p.gradientPink;
  static LinearGradient get gradientFull => _p.gradientFull;
}

class AppTheme {
  static ThemeData buildFrom(AppPalette p) {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: p.bg,
      colorScheme: ColorScheme.dark(
        primary: p.accent,
        secondary: p.accent2,
        tertiary: p.accent3,
        surface: p.surface,
        error: p.error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: p.textPrimary,
        onError: Colors.white,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(base.textTheme).apply(
        bodyColor: p.textPrimary,
        displayColor: p.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: p.textPrimary),
        titleTextStyle: GoogleFonts.syne(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: p.textPrimary,
        ),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1),
    );
  }

  /// Construit le thème à partir de la palette actuellement active.
  static ThemeData get current => buildFrom(ThemeController.to.palette.value);
}
