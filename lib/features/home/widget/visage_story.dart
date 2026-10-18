import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

// ─── EFFETS DE VISAGE SUR LES PHOTOS DE STORY ─────────────────────
// Le visage est repéré SUR LE TÉLÉPHONE (Google ML Kit, rien n'est envoyé
// sur Internet), puis l'effet choisi (lunettes, couronne, yeux cœurs…) est
// posé dessus et gravé dans la photo à la publication.
// Photos seulement : en vidéo, il faudrait suivre le visage image par
// image (moteur de réalité augmentée), prévu plus tard.

class VisageDetecte {
  final Rect cadre; // en pixels de l'image
  final Offset? oeilGauche, oeilDroit; // à gauche / à droite DE L'IMAGE
  final Offset? bouche;
  const VisageDetecte(this.cadre, this.oeilGauche, this.oeilDroit, this.bouche);

  Offset get centre => cadre.center;

  /// Écart entre les yeux (ou une estimation depuis la largeur du visage).
  double get ecartYeux {
    final g = oeilGauche, d = oeilDroit;
    if (g != null && d != null) return (d - g).distance;
    return cadre.width * 0.4;
  }

  /// Inclinaison de la tête (radians), d'après la ligne des yeux.
  double get inclinaison {
    final g = oeilGauche, d = oeilDroit;
    if (g == null || d == null) return 0;
    return math.atan2(d.dy - g.dy, d.dx - g.dx);
  }

  Offset get milieuYeux {
    final g = oeilGauche, d = oeilDroit;
    if (g != null && d != null) return (g + d) / 2;
    return Offset(cadre.center.dx, cadre.top + cadre.height * 0.4);
  }
}

class ResultatVisages {
  final List<VisageDetecte> visages;
  final Size tailleImage;
  const ResultatVisages(this.visages, this.tailleImage);
}

/// Repère les visages d'une photo (null si l'analyse est impossible).
Future<ResultatVisages?> detecterVisages(String chemin) async {
  final detecteur = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.08,
    ),
  );
  try {
    final faces =
        await detecteur.processImage(InputImage.fromFilePath(chemin));
    // Taille de l'image telle que Flutter l'affiche (orientation appliquée)
    final codec =
        await ui.instantiateImageCodec(await File(chemin).readAsBytes());
    final image = (await codec.getNextFrame()).image;
    final taille = Size(image.width.toDouble(), image.height.toDouble());
    image.dispose();
    Offset? point(Face f, FaceLandmarkType t) {
      final p = f.landmarks[t]?.position;
      return p == null ? null : Offset(p.x.toDouble(), p.y.toDouble());
    }

    final visages = faces.map((f) {
      final a = point(f, FaceLandmarkType.leftEye);
      final b = point(f, FaceLandmarkType.rightEye);
      // Rangés de gauche à droite dans l'image (selfie ou non)
      final (g, d) = (a != null && b != null && a.dx > b.dx) ? (b, a) : (a, b);
      return VisageDetecte(
          f.boundingBox, g, d, point(f, FaceLandmarkType.bottomMouth));
    }).toList()
      ..sort((x, y) => y.cadre.width.compareTo(x.cadre.width));
    return ResultatVisages(visages.take(4).toList(), taille);
  } catch (e) {
    debugPrint('Détection de visage impossible : $e');
    return null;
  } finally {
    detecteur.close();
  }
}

class EffetVisage {
  final String id;
  final String nom;
  final String emoji;
  const EffetVisage(this.id, this.nom, this.emoji);

  static const tous = [
    EffetVisage('aucun', 'Aucun', '🚫'),
    EffetVisage('lunettes', 'Lunettes', '🕶️'),
    EffetVisage('couronne', 'Couronne', '👑'),
    EffetVisage('coeurs', 'Yeux cœurs', '😍'),
    EffetVisage('fleurs', 'Fleurs', '🌸'),
    EffetVisage('aureole', 'Auréole', '😇'),
    EffetVisage('paillettes', 'Paillettes', '✨'),
    EffetVisage('feu', 'En feu', '🔥'),
  ];
}

/// Effet posé sur chaque visage, dans le même repère que la photo
/// (affichée en BoxFit.contain).
class CoucheEffetsVisage extends StatelessWidget {
  final ResultatVisages resultat;
  final String effet;
  const CoucheEffetsVisage(
      {super.key, required this.resultat, required this.effet});

  @override
  Widget build(BuildContext context) {
    if (effet == 'aucun') return const SizedBox.shrink();
    return IgnorePointer(
      child: LayoutBuilder(builder: (_, box) {
        final img = resultat.tailleImage;
        if (img.isEmpty) return const SizedBox.shrink();
        // Rectangle de la photo à l'écran (BoxFit.contain, centrée)
        final k = math.min(box.maxWidth / img.width, box.maxHeight / img.height);
        final dx = (box.maxWidth - img.width * k) / 2;
        final dy = (box.maxHeight - img.height * k) / 2;
        Offset ecran(Offset p) => Offset(dx + p.dx * k, dy + p.dy * k);

        final elements = <Widget>[];
        for (final v in resultat.visages) {
          elements.addAll(_effet(v, ecran, k));
        }
        return Stack(clipBehavior: Clip.none, children: elements);
      }),
    );
  }

  /// Emoji centré sur [centre] (écran), de largeur ~[taille], incliné.
  Widget _emoji(String e, Offset centre, double taille, double angle) =>
      Positioned(
        left: centre.dx - taille,
        top: centre.dy - taille,
        width: taille * 2,
        height: taille * 2,
        child: Center(
          child: Transform.rotate(
            angle: angle,
            child: Text(e,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: taille * 0.86, height: 1)),
          ),
        ),
      );

  List<Widget> _effet(VisageDetecte v, Offset Function(Offset) ecran, double k) {
    final angle = v.inclinaison;
    final largeur = v.cadre.width * k;
    final ecart = v.ecartYeux * k;
    // Vecteur « vers le haut » de la tête (suit l'inclinaison)
    final versHaut = Offset(math.sin(angle), -math.cos(angle));
    // Le cadre du visage s'arrête vers la racine des cheveux : le haut du
    // crâne est un peu plus haut (couronne, fleurs, auréole posées dessus)
    final haut = ecran(Offset(v.cadre.center.dx, v.cadre.top)) +
        versHaut * largeur * 0.22;
    switch (effet) {
      case 'lunettes':
        return [_emoji('🕶️', ecran(v.milieuYeux), ecart * 1.25, angle)];
      case 'couronne':
        return [_emoji('👑', haut + versHaut * largeur * 0.35, largeur * 0.42, angle)];
      case 'coeurs':
        return [
          if (v.oeilGauche != null)
            _emoji('❤️', ecran(v.oeilGauche!), ecart * 0.42, angle),
          if (v.oeilDroit != null)
            _emoji('❤️', ecran(v.oeilDroit!), ecart * 0.42, angle),
        ];
      case 'fleurs':
        final cote = Offset(math.cos(angle), math.sin(angle));
        return [
          for (var i = -2; i <= 2; i++)
            _emoji(
                ['🌸', '🌺', '🌼', '🌺', '🌸'][i + 2],
                haut + cote * (i * largeur * 0.2) +
                    versHaut * (largeur * (0.04 - 0.03 * i.abs())),
                largeur * 0.13,
                angle + i * 0.12),
        ];
      case 'aureole':
        final c = haut + versHaut * largeur * 0.28;
        return [
          Positioned(
            left: c.dx - largeur * 0.38,
            top: c.dy - largeur * 0.11,
            width: largeur * 0.76,
            height: largeur * 0.22,
            child: Transform.rotate(
              angle: angle,
              child: CustomPaint(painter: _Aureole()),
            ),
          ),
        ];
      case 'paillettes':
        final bas = Offset(-versHaut.dx, -versHaut.dy);
        return [
          if (v.oeilGauche != null)
            _emoji('✨', ecran(v.oeilGauche!) + bas * ecart * 0.7, ecart * 0.38, angle),
          if (v.oeilDroit != null)
            _emoji('✨', ecran(v.oeilDroit!) + bas * ecart * 0.7, ecart * 0.38, angle),
          _emoji('✨', haut + versHaut * largeur * 0.08, ecart * 0.3, angle),
        ];
      case 'feu':
        final cote = Offset(math.cos(angle), math.sin(angle));
        return [
          for (var i = -1; i <= 1; i++)
            _emoji('🔥', haut + cote * (i * largeur * 0.26) + versHaut * largeur * (0.12 - 0.05 * i.abs()),
                largeur * (i == 0 ? 0.22 : 0.17), angle),
        ];
    }
    return const [];
  }
}

class _Aureole extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final halo = Paint()
      ..color = const Color(0x88FFE27A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.45
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.height * 0.2);
    final anneau = Paint()
      ..shader = const LinearGradient(
              colors: [Color(0xFFFFF4B0), Color(0xFFFFC83D), Color(0xFFFFF4B0)])
          .createShader(r)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.22;
    final ovale = r.deflate(size.height * 0.2);
    canvas.drawOval(ovale, halo);
    canvas.drawOval(ovale, anneau);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Bandeau des effets (éditeur).
class BandeauEffetsVisage extends StatelessWidget {
  final String effetActif;
  final ValueChanged<String> onChoix;
  const BandeauEffetsVisage(
      {super.key, required this.effetActif, required this.onChoix});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: EffetVisage.tous.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final e = EffetVisage.tous[i];
          final actif = e.id == effetActif;
          return GestureDetector(
            onTap: () => onChoix(e.id),
            child: Column(children: [
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white10,
                  border: Border.all(
                      color: actif ? Colors.white : Colors.white24,
                      width: actif ? 3 : 1.5),
                ),
                child: Text(e.emoji, style: const TextStyle(fontSize: 26)),
              ),
              const SizedBox(height: 4),
              Text(e.nom.tr,
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
