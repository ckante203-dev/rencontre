import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // ── Couleurs par RÔLE (préparation du fond blanc) ──────────────────
  // Règle : ne plus écrire Colors.white / Colors.black pour un texte ou
  // une icône posé sur le FOND de l'écran → AppColors.textPrimary /
  // textMuted. Les couleurs en dur ne restent que pour ces rôles :

  /// Fond clair (palette « Blanc ») ?
  static bool get clair => _p.clair;

  /// Texte / icône sur un bouton accent ou dégradé (blanc dans les deux
  /// modes : en fond blanc, les boutons sont noirs)
  static const Color surAccent = Colors.white;

  /// Texte / icône posé sur une PHOTO ou une VIDÉO (toujours blanc)
  static const Color surMedia = Colors.white;

  /// Voile sombre sur une photo pour lire le texte (toujours sombre)
  static const Color voileMedia = Color(0x8A000000);

  /// Barre d'état (heure, batterie) adaptée au fond de l'écran
  static SystemUiOverlayStyle get barreSysteme => _p.barreSysteme;
}

class AppTheme {
  static ThemeData buildFrom(AppPalette p) {
    // Fond blanc ou sombre selon la palette
    final base = p.clair
        ? ThemeData.light(useMaterial3: true)
        : ThemeData.dark(useMaterial3: true);
    final schema = p.clair
        ? ColorScheme.light(
            primary: p.accent,
            secondary: p.accent2,
            tertiary: p.accent3,
            surface: p.surface,
            error: p.error,
            onPrimary: AppColors.surAccent,
            onSecondary: AppColors.surAccent,
            onSurface: p.textPrimary,
            onError: Colors.white,
          )
        : ColorScheme.dark(
            primary: p.accent,
            secondary: p.accent2,
            tertiary: p.accent3,
            surface: p.surface,
            error: p.error,
            onPrimary: AppColors.surAccent,
            onSecondary: AppColors.surAccent,
            onSurface: p.textPrimary,
            onError: Colors.white,
          );
    return base.copyWith(
      brightness: p.luminosite,
      scaffoldBackgroundColor: p.bg,
      colorScheme: schema,
      textTheme: GoogleFonts.poppinsTextTheme(base.textTheme).apply(
        bodyColor: p.textPrimary,
        displayColor: p.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        systemOverlayStyle: p.barreSysteme,
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
