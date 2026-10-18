import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

// ─── FILTRES DES STORIES ──────────────────────────────────────────
// Glisser à gauche / à droite dans la caméra (ou bouton « Filtres » de
// l'éditeur) pour changer de filtre, en direct.
//
// Pensés pour SUBLIMER LES PEAUX NOIRES ET MATES : aucun filtre ne blanchit
// la peau (pas de baisse de saturation des tons chauds, pas d'éclaircissement
// global qui délave) — on joue sur la chaleur, le contraste et l'éclat.
//
// Photo : le filtre est « gravé » dans l'image à la publication.
// Vidéo : seul l'identifiant est enregistré (stories.filtre, SQL 085) et le
// téléphone de celui qui regarde l'applique — instantané, sans réencodage.

class FiltreStory {
  final String id;
  final String nom;
  final String emoji;

  /// Matrice de couleur 4×5 (ColorFilter.matrix), null = aucun effet.
  final List<double>? matrice;
  const FiltreStory(this.id, this.nom, this.emoji, this.matrice);

  bool get neutre => matrice == null;

  static final List<FiltreStory> tous = [
    const FiltreStory('normal', 'Normal', '⚪', null),
    FiltreStory('ebene', 'Ébène', '🖤',
        _compose([_contraste(1.18), _saturation(1.12), _chaleur(0.06), _eclat(-0.02)])),
    FiltreStory('or', 'Or', '✨',
        _compose([_chaleur(0.14), _saturation(1.15), _contraste(1.06), _eclat(0.03)])),
    FiltreStory('miel', 'Miel', '🍯',
        _compose([_chaleur(0.10), _ombres(0.06), _contraste(0.94), _saturation(1.05)])),
    FiltreStory('glam', 'Glam', '💋',
        _compose([_saturation(1.30), _contraste(1.12), _teinte(0.04, -0.01, 0.02)])),
    FiltreStory('soleil', 'Soleil', '☀️',
        _compose([_chaleur(0.18), _eclat(0.06), _saturation(1.10)])),
    FiltreStory('lagune', 'Lagune', '🌊',
        _compose([_teinte(-0.05, 0.03, 0.08), _contraste(1.08), _saturation(1.05)])),
    FiltreStory('nuit', 'Nuit', '🌙',
        _compose([_teinte(-0.03, -0.01, 0.07), _contraste(1.15), _eclat(-0.05)])),
    FiltreStory('rose', 'Rose', '🌸',
        _compose([_teinte(0.07, -0.02, 0.04), _saturation(1.08), _eclat(0.02)])),
    FiltreStory('vintage', 'Vintage', '📜',
        _compose([_sepia(0.45), _contraste(0.92), _ombres(0.05)])),
    FiltreStory('nb', 'Noir & blanc', '🎞️',
        _compose([_saturation(0), _contraste(1.25)])),
  ];

  static FiltreStory parId(String? id) =>
      tous.firstWhere((f) => f.id == id, orElse: () => tous.first);

  // ─── Construction des matrices (5×5 composées, renvoyées en 4×5) ───
  static List<double> _compose(List<List<double>> etapes) {
    var m = _identite5();
    for (final e in etapes) {
      m = _multiplier(_vers5(e), m);
    }
    return m.sublist(0, 20);
  }

  static List<double> _identite5() => [
        1, 0, 0, 0, 0, //
        0, 1, 0, 0, 0,
        0, 0, 1, 0, 0,
        0, 0, 0, 1, 0,
        0, 0, 0, 0, 1,
      ];

  static List<double> _vers5(List<double> m4x5) => [...m4x5, 0, 0, 0, 0, 1];

  static List<double> _multiplier(List<double> a, List<double> b) {
    final r = List<double>.filled(25, 0);
    for (var i = 0; i < 5; i++) {
      for (var j = 0; j < 5; j++) {
        var s = 0.0;
        for (var k = 0; k < 5; k++) {
          s += a[i * 5 + k] * b[k * 5 + j];
        }
        r[i * 5 + j] = s;
      }
    }
    return r;
  }

  // Saturation (luminance Rec. 709)
  static List<double> _saturation(double s) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final ir = (1 - s) * lr, ig = (1 - s) * lg, ib = (1 - s) * lb;
    return [
      ir + s, ig, ib, 0, 0, //
      ir, ig + s, ib, 0, 0,
      ir, ig, ib + s, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }

  // Contraste autour du gris moyen
  static List<double> _contraste(double c) {
    final t = 128 * (1 - c);
    return [
      c, 0, 0, 0, t, //
      0, c, 0, 0, t,
      0, 0, c, 0, t,
      0, 0, 0, 1, 0,
    ];
  }

  // Éclat (décalage de luminosité, en fraction de 255)
  static List<double> _eclat(double b) {
    final d = 255 * b;
    return [
      1, 0, 0, 0, d, //
      0, 1, 0, 0, d,
      0, 0, 1, 0, d,
      0, 0, 0, 1, 0,
    ];
  }

  // Chaleur : plus de rouge / jaune, moins de bleu
  static List<double> _chaleur(double w) => _teinte(w, w * 0.45, -w * 0.8);

  // Teinte (décalages R, G, B en fraction de 255)
  static List<double> _teinte(double r, double g, double b) => [
        1, 0, 0, 0, 255 * r, //
        0, 1, 0, 0, 255 * g,
        0, 0, 1, 0, 255 * b,
        0, 0, 0, 1, 0,
      ];

  // Ombres relevées (doux, sans délaver les tons chauds)
  static List<double> _ombres(double o) {
    final k = 1 - o;
    final d = 255 * o;
    return [
      k, 0, 0, 0, d, //
      0, k, 0, 0, d,
      0, 0, k, 0, d,
      0, 0, 0, 1, 0,
    ];
  }

  static List<double> _sepia(double force) {
    final f = force.clamp(0.0, 1.0);
    final s = [
      0.393, 0.769, 0.189, 0, 0, //
      0.349, 0.686, 0.168, 0, 0,
      0.272, 0.534, 0.131, 0, 0,
      0, 0, 0, 1, 0,
    ];
    final id = [
      1, 0, 0, 0, 0, //
      0, 1, 0, 0, 0,
      0, 0, 1, 0, 0,
      0, 0, 0, 1, 0,
    ];
    return List<double>.generate(20, (i) => id[i] * (1 - f) + s[i] * f);
  }
}

/// Applique un filtre à son enfant (rien si « Normal » ou inconnu).
class AvecFiltre extends StatelessWidget {
  final String? filtre;
  final Widget child;
  const AvecFiltre({super.key, required this.filtre, required this.child});

  @override
  Widget build(BuildContext context) {
    final m = FiltreStory.parId(filtre).matrice;
    if (m == null) return child;
    return ColorFiltered(colorFilter: ColorFilter.matrix(m), child: child);
  }
}

/// Nom du filtre qui apparaît puis s'efface quand on change de filtre.
class NomFiltre extends StatelessWidget {
  final FiltreStory filtre;

  /// Change à chaque changement de filtre pour relancer l'animation.
  final int compteur;
  const NomFiltre({super.key, required this.filtre, required this.compteur});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        key: ValueKey(compteur),
        tween: Tween(begin: 1, end: 0),
        duration: const Duration(milliseconds: 1400),
        curve: const Interval(0.5, 1, curve: Curves.easeOut),
        builder: (_, v, __) => Opacity(
          opacity: compteur == 0 ? 0 : v,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(filtre.emoji, style: const TextStyle(fontSize: 34)),
            const SizedBox(height: 4),
            Text(filtre.nom.tr,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    shadows: [Shadow(blurRadius: 8)])),
          ]),
        ),
      ),
    );
  }
}

/// Bandeau de vignettes des filtres (éditeur) : touche pour choisir.
class BandeauFiltres extends StatelessWidget {
  final String filtreActif;
  final ValueChanged<String> onChoix;

  /// Aperçu miniature (la photo, ou la photo de profil pour une vidéo).
  final Widget Function(FiltreStory f) vignette;
  const BandeauFiltres({
    super.key,
    required this.filtreActif,
    required this.onChoix,
    required this.vignette,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: FiltreStory.tous.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final f = FiltreStory.tous[i];
          final actif = f.id == filtreActif;
          return GestureDetector(
            onTap: () => onChoix(f.id),
            child: Column(children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: actif ? Colors.white : Colors.white24,
                      width: actif ? 3 : 1.5),
                ),
                child: ClipOval(child: vignette(f)),
              ),
              const SizedBox(height: 4),
              Text(f.nom.tr,
                  style: TextStyle(
                      color: actif ? Colors.white : Colors.white70,
                      fontSize: 11,
                      fontWeight: actif ? FontWeight.w800 : FontWeight.w500)),
            ]),
          );
        },
      ),
    );
  }
}

/// Indice de glisser (petits points sous le nom), pour la caméra.
class PointsFiltres extends StatelessWidget {
  final int index;
  const PointsFiltres({super.key, required this.index});

  @override
  Widget build(BuildContext context) {
    final n = FiltreStory.tous.length;
    return IgnorePointer(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < n; i++)
          Container(
            width: i == index ? 8 : 5,
            height: i == index ? 8 : 5,
            margin: EdgeInsets.symmetric(horizontal: math.max(2, 3 - n / 8)),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i == index ? Colors.white : Colors.white38,
            ),
          ),
      ]),
    );
  }
}
