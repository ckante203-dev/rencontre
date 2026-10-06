import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rencontre/core/theme/app_palette.dart';

/// Contraste WCAG entre deux couleurs (1 à 21).
double contraste(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

void main() {
  final palettes = [
    ...AppPalettes.all.values,
    ...AppPalettes.enPreparation.values,
  ];

  group('Lisibilité des thèmes (fond sombre et fond blanc)', () {
    for (final p in palettes) {
      test('${p.label} : texte principal lisible sur le fond', () {
        expect(contraste(p.textPrimary, p.bg), greaterThanOrEqualTo(7));
        expect(contraste(p.textPrimary, p.surface), greaterThanOrEqualTo(7));
      });
      test('${p.label} : texte secondaire lisible sur le fond', () {
        expect(contraste(p.textMuted, p.bg), greaterThanOrEqualTo(4.5));
      });
      test('${p.label} : texte blanc lisible sur les boutons', () {
        expect(contraste(Colors.white, p.accent), greaterThanOrEqualTo(3));
      });
    }

    test('La palette Blanc est claire, les autres sombres', () {
      expect(AppPalettes.blanc.clair, isTrue);
      expect(AppPalettes.blanc.luminosite, Brightness.light);
      for (final p in AppPalettes.all.values) {
        expect(p.clair, isFalse, reason: p.label);
      }
    });

    test('Blanc reste hors du choix de thème (en préparation)', () {
      expect(AppPalettes.all.containsKey('blanc'), isFalse);
      expect(AppPalettes.resoudre('blanc'), AppPalettes.blanc);
    });
  });
}
