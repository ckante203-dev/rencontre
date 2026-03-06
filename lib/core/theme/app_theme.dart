import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const bg = Color(0xFF0A0A0F);
  static const surface = Color(0xFF13131A);
  static const surface2 = Color(0xFF1C1C28);
  static const border = Color(0xFF2A2A3D);
  static const accent = Color(0xFFFF3CAC);
  static const accent2 = Color(0xFF7B2FFF);
  static const accent3 = Color(0xFF00F5D4);
  static const yellow = Color(0xFFFFDD57);
  static const textPrimary = Color(0xFFF0F0FF);
  static const textMuted = Color(0xFF6B6B8A);
  static const online = Color(0xFF00E676);
  static const error = Color(0xFFFF5252);

  static LinearGradient get gradientPink => const LinearGradient(
        colors: [accent, accent2],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient get gradientFull => const LinearGradient(
        colors: [accent, accent2, accent3],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}

class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accent,
        secondary: AppColors.accent2,
        tertiary: AppColors.accent3,
        surface: AppColors.surface,
        error: AppColors.error,
      ),
      textTheme: GoogleFonts.spaceGroteskTextTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: GoogleFonts.syne(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
      ),
    );
  }
}
