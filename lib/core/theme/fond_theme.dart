import 'dart:math';

import 'package:flutter/material.dart';
import 'app_palette.dart';
import 'theme_controller.dart';

/// Fond d'un écran de liste : la couleur du thème + son motif (thèmes
/// illustrés). Sans [palette], suit le thème actif.
class FondTheme extends StatelessWidget {
  final Widget child;
  final AppPalette? palette;
  const FondTheme({super.key, required this.child, this.palette});

  @override
  Widget build(BuildContext context) {
    final p = palette ?? ThemeController.to.palette.value;
    return ColoredBox(
      color: p.bg,
      child: p.motif == Motif.aucun
          ? child
          : CustomPaint(
              painter: MotifPainter(p),
              child: child,
            ),
    );
  }
}

/// Dessine le motif d'un thème : petits symboles discrets répartis
/// régulièrement (position « au hasard » mais identique à chaque image).
class MotifPainter extends CustomPainter {
  final AppPalette p;
  MotifPainter(this.p);

  static const _pas = 74.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (p.motif == Motif.vagues) {
      _vagues(canvas, size);
      return;
    }
    final hasard = Random(7);
    final couleur = p.accent3.withValues(alpha: 0.10);
    for (double y = 0; y < size.height + _pas; y += _pas) {
      final decale = ((y / _pas).round().isOdd) ? _pas / 2 : 0.0;
      for (double x = -_pas / 2; x < size.width + _pas; x += _pas) {
        final cx = x + decale + hasard.nextDouble() * 18 - 9;
        final cy = y + hasard.nextDouble() * 18 - 9;
        final taille = 10 + hasard.nextDouble() * 9;
        final angle = (hasard.nextDouble() - 0.5) * 0.7;
        canvas.save();
        canvas.translate(cx, cy);
        canvas.rotate(angle);
        switch (p.motif) {
          case Motif.coeurs:
            _coeur(canvas, taille, couleur);
          case Motif.etoiles:
            _etoile(canvas, taille * 0.8, couleur);
          case Motif.citrouilles:
            _citrouille(canvas, taille, couleur);
          case Motif.flocons:
            _flocon(canvas, taille * 0.8, couleur);
          case Motif.vagues:
          case Motif.aucun:
            break;
        }
        canvas.restore();
      }
    }
  }

  void _coeur(Canvas c, double t, Color couleur) {
    final h = t / 2;
    final chemin = Path()
      ..moveTo(0, h * 0.9)
      ..cubicTo(-h * 1.6, -h * 0.2, -h * 0.7, -h * 1.3, 0, -h * 0.45)
      ..cubicTo(h * 0.7, -h * 1.3, h * 1.6, -h * 0.2, 0, h * 0.9)
      ..close();
    c.drawPath(chemin, Paint()..color = couleur);
  }

  void _etoile(Canvas c, double t, Color couleur) {
    // Étoile scintillante à 4 branches
    final r = t / 2;
    final chemin = Path()
      ..moveTo(0, -r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..quadraticBezierTo(0, 0, 0, r)
      ..quadraticBezierTo(0, 0, -r, 0)
      ..quadraticBezierTo(0, 0, 0, -r)
      ..close();
    c.drawPath(chemin, Paint()..color = couleur.withValues(alpha: 0.16));
  }

  void _citrouille(Canvas c, double t, Color couleur) {
    final r = t / 2;
    final peinture = Paint()..color = couleur;
    for (final dx in [-r * 0.45, r * 0.45, 0.0]) {
      c.drawOval(
          Rect.fromCenter(
              center: Offset(dx, 0), width: r * 1.1, height: r * 1.5),
          peinture);
    }
    c.drawRect(Rect.fromLTWH(-r * 0.1, -r, r * 0.2, r * 0.35), peinture);
  }

  void _flocon(Canvas c, double t, Color couleur) {
    final r = t / 2;
    final trait = Paint()
      ..color = couleur.withValues(alpha: 0.16)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 3; i++) {
      final a = i * pi / 3;
      final d = Offset(cos(a) * r, sin(a) * r);
      c.drawLine(-d, d, trait);
    }
  }

  void _vagues(Canvas c, Size size) {
    final trait = Paint()
      ..color = p.accent3.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    const ecart = 46.0;
    int ligne = 0;
    for (double y = 20; y < size.height + ecart; y += ecart, ligne++) {
      final chemin = Path()..moveTo(0, y);
      final phase = ligne.isOdd ? pi : 0.0;
      for (double x = 0; x <= size.width; x += 6) {
        chemin.lineTo(x, y + sin(x / 28 + phase) * 6);
      }
      c.drawPath(chemin, trait);
    }
  }

  @override
  bool shouldRepaint(MotifPainter old) => old.p.id != p.id;
}
