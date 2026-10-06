import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppPalette {
  final String id;
  final String label;
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color border;
  final Color accent;
  final Color accent2;
  final Color accent3;
  final Color yellow;
  final Color textPrimary;
  final Color textMuted;
  final Color online;
  final Color error;

  /// Fond clair (palette « Blanc ») : textes sombres, barre d'état sombre
  final bool clair;

  const AppPalette({
    required this.id,
    required this.label,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.border,
    required this.accent,
    required this.accent2,
    required this.accent3,
    required this.yellow,
    required this.textPrimary,
    required this.textMuted,
    required this.online,
    required this.error,
    this.clair = false,
  });

  Brightness get luminosite => clair ? Brightness.light : Brightness.dark;

  /// Icônes de la barre d'état (heure, batterie) lisibles sur le fond
  SystemUiOverlayStyle get barreSysteme => (clair
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light)
      .copyWith(statusBarColor: Colors.transparent);

  LinearGradient get gradientPink => LinearGradient(
        colors: [accent, accent2],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  LinearGradient get gradientFull => LinearGradient(
        colors: [accent, accent2, accent3],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}

// Thème « Zamu » (couleurs du logo, par défaut) + thèmes « pro » : fonds
// neutres, un seul accent profond (le dégradé des boutons reste dans la
// même teinte : rendu quasi uni, sobre), texte secondaire gris. Les anciens
// thèmes néon sont redirigés (voir resoudre).
class AppPalettes {
  // Couleurs du logo : fond #0D0D1A, « Z » magenta #D637C5 → violet #A433E5
  static const zamu = AppPalette(
    id: 'zamu',
    label: 'Zamu',
    bg: Color(0xFF0D0D1A),
    surface: Color(0xFF151526),
    surface2: Color(0xFF1D1D33),
    border: Color(0xFF2E2E4A),
    accent: Color(0xFFD637C5),
    accent2: Color(0xFFA433E5),
    accent3: Color(0xFFE47BDA),
    yellow: Color(0xFFF5C451),
    textPrimary: Color(0xFFF4F4F8),
    textMuted: Color(0xFF9E9CB3),
    online: Color(0xFF22C55E),
    error: Color(0xFFEF4444),
  );

  static const minuit = AppPalette(
    id: 'minuit',
    label: 'Minuit',
    bg: Color(0xFF0E0F14),
    surface: Color(0xFF16181F),
    surface2: Color(0xFF1E212A),
    border: Color(0xFF2C303B),
    accent: Color(0xFFC2185B),
    accent2: Color(0xFFA3154D),
    accent3: Color(0xFFE35D8A),
    yellow: Color(0xFFF5C451),
    textPrimary: Color(0xFFF4F5F7),
    textMuted: Color(0xFF9BA1AD),
    online: Color(0xFF22C55E),
    error: Color(0xFFEF4444),
  );

  static const graphite = AppPalette(
    id: 'graphite',
    label: 'Graphite',
    bg: Color(0xFF111214),
    surface: Color(0xFF18191C),
    surface2: Color(0xFF202226),
    border: Color(0xFF2E3036),
    accent: Color(0xFF5B5BD6),
    accent2: Color(0xFF4A4AC0),
    accent3: Color(0xFF8B8BF0),
    yellow: Color(0xFFF5C451),
    textPrimary: Color(0xFFF4F5F7),
    textMuted: Color(0xFF9BA1AD),
    online: Color(0xFF22C55E),
    error: Color(0xFFEF4444),
  );

  static const saphir = AppPalette(
    id: 'saphir',
    label: 'Saphir',
    bg: Color(0xFF0A1020),
    surface: Color(0xFF111A2E),
    surface2: Color(0xFF18233A),
    border: Color(0xFF263552),
    accent: Color(0xFF2F6FEB),
    accent2: Color(0xFF2459C9),
    accent3: Color(0xFF6EA0FF),
    yellow: Color(0xFFF5C451),
    textPrimary: Color(0xFFF4F5F7),
    textMuted: Color(0xFF9BA1AD),
    online: Color(0xFF22C55E),
    error: Color(0xFFEF4444),
  );

  static const emeraude = AppPalette(
    id: 'emeraude',
    label: 'Émeraude',
    bg: Color(0xFF0B110F),
    surface: Color(0xFF121A17),
    surface2: Color(0xFF19231F),
    border: Color(0xFF27352F),
    accent: Color(0xFF12A37A),
    accent2: Color(0xFF0E8664),
    accent3: Color(0xFF4FD1A5),
    yellow: Color(0xFFF5C451),
    textPrimary: Color(0xFFF4F5F7),
    textMuted: Color(0xFF9BA1AD),
    online: Color(0xFF22C55E),
    error: Color(0xFFEF4444),
  );

  static const champagne = AppPalette(
    id: 'champagne',
    label: 'Champagne',
    bg: Color(0xFF0F0E0C),
    surface: Color(0xFF181613),
    surface2: Color(0xFF211E1A),
    border: Color(0xFF37322A),
    accent: Color(0xFFC9A24B),
    accent2: Color(0xFFA8853A),
    accent3: Color(0xFFE6C77D),
    yellow: Color(0xFFF5C451),
    textPrimary: Color(0xFFF4F5F7),
    textMuted: Color(0xFF9BA1AD),
    online: Color(0xFF22C55E),
    error: Color(0xFFEF4444),
  );

  /// Fond blanc avec un seul thème « noir » : boutons et accents noirs ou
  /// gris foncé, texte blanc sur ces boutons. EN PRÉPARATION : absente de
  /// [all] (donc du choix de thème) tant que les écrans ne sont pas prêts.
  static const blanc = AppPalette(
    id: 'blanc',
    label: 'Blanc',
    bg: Color(0xFFFFFFFF),
    surface: Color(0xFFF4F4F6),
    surface2: Color(0xFFEAEAEE),
    border: Color(0xFFE0E0E6),
    accent: Color(0xFF111111),
    accent2: Color(0xFF2C2C2E),
    accent3: Color(0xFF48484A),
    yellow: Color(0xFFE0A800),
    textPrimary: Color(0xFF111111),
    textMuted: Color(0xFF6E6E73),
    online: Color(0xFF16A34A),
    error: Color(0xFFDC2626),
    clair: true,
  );

  /// Thème par défaut (nouveaux comptes) : les couleurs du logo.
  static const defaut = zamu;

  static const Map<String, AppPalette> all = {
    'zamu': zamu,
    'minuit': minuit,
    'graphite': graphite,
    'saphir': saphir,
    'emeraude': emeraude,
    'champagne': champagne,
  };

  /// Anciens thèmes (néon, retirés) → thème pro le plus proche.
  static const Map<String, String> _anciens = {
    'dark': 'zamu',
    'sunset': 'minuit',
    'aurore': 'emeraude',
    'lagon': 'saphir',
    'or_noir': 'champagne',
  };

  /// Palettes en préparation : utilisables, mais pas encore proposées
  static const Map<String, AppPalette> enPreparation = {'blanc': blanc};

  /// Palette pour un id enregistré (ancien ou nouveau), sinon null.
  static AppPalette? resoudre(String? id) =>
      all[id] ?? enPreparation[id] ?? all[_anciens[id]];
}

/// Dégradés sobres des avatars sans photo (initiale) : teintes sourdes,
/// lisibles avec du texte blanc, sans néon.
const List<List<Color>> degradesAvatar = [
  [Color(0xFF4B5263), Color(0xFF2E333F)], // ardoise
  [Color(0xFF7A3B55), Color(0xFF4A2335)], // bordeaux
  [Color(0xFF34507A), Color(0xFF213350)], // bleu nuit
  [Color(0xFF2F6B58), Color(0xFF1D4337)], // vert sapin
  [Color(0xFF7D6236), Color(0xFF4E3D22)], // bronze
  [Color(0xFF55457E), Color(0xFF352B52)], // prune
  [Color(0xFF6E4A3E), Color(0xFF452E26)], // terre
  [Color(0xFF3E6370), Color(0xFF263E46)], // pétrole
];
