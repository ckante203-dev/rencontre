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
    textPrimary: Color(0xFFFFFFFF),
    textMuted: Color(0xB3FFFFFF),
    online: Color(0xFF00E676),
    error: Color(0xFFFF5252),
  );

  static const aurore = AppPalette(
    id: 'aurore',
    label: 'Aurore boréale',
    bg: Color(0xFF050A12),
    surface: Color(0xFF0C1522),
    surface2: Color(0xFF13202F),
    border: Color(0xFF2A3B52),
    accent: Color(0xFF0E9F8A),
    accent2: Color(0xFF6A3DF0),
    accent3: Color(0xFF5CF2C8),
    yellow: Color(0xFFFFDD57),
    textPrimary: Color(0xFFFFFFFF),
    textMuted: Color(0xB3FFFFFF),
    online: Color(0xFF00E676),
    error: Color(0xFFFF5252),
  );

  static const lagon = AppPalette(
    id: 'lagon',
    label: 'Lagon',
    bg: Color(0xFF040A16),
    surface: Color(0xFF0A1528),
    surface2: Color(0xFF112038),
    border: Color(0xFF263D63),
    accent: Color(0xFF0091D5),
    accent2: Color(0xFF3A47D5),
    accent3: Color(0xFF4FE3FF),
    yellow: Color(0xFFFFDD57),
    textPrimary: Color(0xFFFFFFFF),
    textMuted: Color(0xB3FFFFFF),
    online: Color(0xFF00E676),
    error: Color(0xFFFF5252),
  );

  static const sunset = AppPalette(
    id: 'sunset',
    label: 'Sunset tropical',
    bg: Color(0xFF120710),
    surface: Color(0xFF1F0E1B),
    surface2: Color(0xFF2B1426),
    border: Color(0xFF5A2747),
    accent: Color(0xFFE8641C),
    accent2: Color(0xFFD61F8C),
    accent3: Color(0xFFFFB25B),
    yellow: Color(0xFFFFDD57),
    textPrimary: Color(0xFFFFFFFF),
    textMuted: Color(0xB3FFFFFF),
    online: Color(0xFF00E676),
    error: Color(0xFFFF5252),
  );

  static const orNoir = AppPalette(
    id: 'or_noir',
    label: 'Or noir',
    bg: Color(0xFF0B0A08),
    surface: Color(0xFF16130E),
    surface2: Color(0xFF211C14),
    border: Color(0xFF4A3D26),
    accent: Color(0xFFB07A1E),
    accent2: Color(0xFF8A4B12),
    accent3: Color(0xFFF5D68A),
    yellow: Color(0xFFFFDD57),
    textPrimary: Color(0xFFFFFFFF),
    textMuted: Color(0xB3FFFFFF),
    online: Color(0xFF00E676),
    error: Color(0xFFFF5252),
  );

  static const Map<String, AppPalette> all = {
    'dark': dark,
    'aurore': aurore,
    'lagon': lagon,
    'sunset': sunset,
    'or_noir': orNoir,
  };
}
