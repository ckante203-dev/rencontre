import 'package:flutter/material.dart';

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
  });

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

class AppPalettes {
  static const dark = AppPalette(
    id: 'dark',
    label: 'Néon rose',
    bg: Color(0xFF0A0A0F),
    surface: Color(0xFF13131A),
    surface2: Color(0xFF1C1C28),
    border: Color(0xFF3F3F5B),
    accent: Color(0xFFFF3CAC),
    accent2: Color(0xFF7B2FFF),
    accent3: Color(0xFFFF6BCB),
    yellow: Color(0xFFFFDD57),
    textPrimary: Color(0xFFF0F0FF),
    textMuted: Color(0xFF84849F),
    online: Color(0xFF00E676),
    error: Color(0xFFFF5252),
  );

  static const blue = AppPalette(
    id: 'blue',
    label: 'Bleu électrique',
    bg: Color(0xFF05070F),
    surface: Color(0xFF0D1226),
    surface2: Color(0xFF141B36),
    border: Color(0xFF323E6C),
    accent: Color(0xFF3B6DFF),
    accent2: Color(0xFF009DCF),
    accent3: Color(0xFF7B2FFF),
    yellow: Color(0xFFFFDD57),
    textPrimary: Color(0xFFEAF1FF),
    textMuted: Color(0xFF7784AF),
    online: Color(0xFF00E676),
    error: Color(0xFFFF5252),
  );

  static const ocean = AppPalette(
    id: 'ocean',
    label: 'Océan turquoise',
    bg: Color(0xFF03110F),
    surface: Color(0xFF08201C),
    surface2: Color(0xFF0D2E28),
    border: Color(0xFF1A5045),
    accent: Color(0xFF00A397),
    accent2: Color(0xFF009EBF),
    accent3: Color(0xFF00FFC2),
    yellow: Color(0xFFFFDD57),
    textPrimary: Color(0xFFE8FFFB),
    textMuted: Color(0xFF5D9C90),
    online: Color(0xFF00E676),
    error: Color(0xFFFF5252),
  );

  static const sunset = AppPalette(
    id: 'sunset',
    label: 'Coucher de soleil',
    bg: Color(0xFF160A0C),
    surface: Color(0xFF261216),
    surface2: Color(0xFF351A20),
    border: Color(0xFF732C37),
    accent: Color(0xFFFF5757),
    accent2: Color(0xFFFF3CAC),
    accent3: Color(0xFFFFB86B),
    yellow: Color(0xFFFFDD57),
    textPrimary: Color(0xFFFFF3F0),
    textMuted: Color(0xFF9F8484),
    online: Color(0xFF00E676),
    error: Color(0xFFFF5252),
  );

  static const forest = AppPalette(
    id: 'forest',
    label: 'Émeraude',
    bg: Color(0xFF040F0B),
    surface: Color(0xFF0A1F17),
    surface2: Color(0xFF0F2E22),
    border: Color(0xFF1C4E3B),
    accent: Color(0xFF00A66F),
    accent2: Color(0xFF00A686),
    accent3: Color(0xFF6BFFB8),
    yellow: Color(0xFFFFDD57),
    textPrimary: Color(0xFFECFFF6),
    textMuted: Color(0xFF5D9E83),
    online: Color(0xFF00E676),
    error: Color(0xFFFF5252),
  );

  static const gold = AppPalette(
    id: 'gold',
    label: 'Or royal',
    bg: Color(0xFF140F04),
    surface: Color(0xFF241B08),
    surface2: Color(0xFF33270D),
    border: Color(0xFF584315),
    accent: Color(0xFFAB9000),
    accent2: Color(0xFFDE7800),
    accent3: Color(0xFFFFEA80),
    yellow: Color(0xFFFFDD57),
    textPrimary: Color(0xFFFFFAEE),
    textMuted: Color(0xFFA09075),
    online: Color(0xFF00E676),
    error: Color(0xFFFF5252),
  );

  static const violet = AppPalette(
    id: 'violet',
    label: 'Violet galaxie',
    bg: Color(0xFF0B0714),
    surface: Color(0xFF160E28),
    surface2: Color(0xFF20153A),
    border: Color(0xFF493379),
    accent: Color(0xFF9253FF),
    accent2: Color(0xFFB026FF),
    accent3: Color(0xFFFF3CAC),
    yellow: Color(0xFFFFDD57),
    textPrimary: Color(0xFFF3EAFF),
    textMuted: Color(0xFF8F7FA9),
    online: Color(0xFF00E676),
    error: Color(0xFFFF5252),
  );

  static const Map<String, AppPalette> all = {
    'dark': dark,
    'blue': blue,
    'ocean': ocean,
    'sunset': sunset,
    'forest': forest,
    'gold': gold,
    'violet': violet,
  };
}
