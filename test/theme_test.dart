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

    test('Thèmes de saison : proposés seulement pendant leur période', () {
      expect(AppPalettes.halloween.disponibleLe(DateTime(2026, 10, 20)), isTrue);
      expect(AppPalettes.halloween.disponibleLe(DateTime(2026, 12, 20)), isFalse);
      // Période à cheval sur le 1er janvier
      expect(AppPalettes.fetes.disponibleLe(DateTime(2026, 12, 24)), isTrue);
      expect(AppPalettes.fetes.disponibleLe(DateTime(2027, 1, 3)), isTrue);
      expect(AppPalettes.fetes.disponibleLe(DateTime(2027, 2, 1)), isFalse);
      final juin = AppPalettes.proposes(DateTime(2027, 6, 1)).map((p) => p.id);
      expect(juin, isNot(contains('halloween')));
      expect(juin, contains('lagune'));
      // Qui a choisi un thème de saison le garde
      expect(
          AppPalettes.proposes(DateTime(2027, 6, 1), actuel: 'fetes')
              .map((p) => p.id),
          contains('fetes'));
    });

    test('Les anciens identifiants restent reconnus', () {
      for (final id in ['minuit', 'graphite', 'dark', 'sunset', 'lagon']) {
        expect(AppPalettes.resoudre(id), isNotNull, reason: id);
      }
    });

    test('Blanc reste hors du choix de thème (en préparation)', () {
      expect(AppPalettes.all.containsKey('blanc'), isFalse);
      expect(AppPalettes.resoudre('blanc'), AppPalettes.blanc);
    });
  });
}
