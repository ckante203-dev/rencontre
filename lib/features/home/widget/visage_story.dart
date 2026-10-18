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
  final Offset? bouche; // bas de la bouche
  final Offset? nez; // base du nez
  final Offset? boucheGauche, boucheDroite;
  const VisageDetecte(this.cadre, this.oeilGauche, this.oeilDroit, this.bouche,
      {this.nez, this.boucheGauche, this.boucheDroite});

  /// Centre de la bouche (ou une estimation).
  Offset get centreBouche {
    final g = boucheGauche, d = boucheDroite, b = bouche;
    if (g != null && d != null) {
      final milieu = (g + d) / 2;
      return b != null ? (milieu * 2 + b) / 3 : milieu;
    }
    return b ?? Offset(cadre.center.dx, cadre.top + cadre.height * 0.78);
  }

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
      final mg = point(f, FaceLandmarkType.leftMouth);
      final md = point(f, FaceLandmarkType.rightMouth);
      final (bg, bd) =
          (mg != null && md != null && mg.dx > md.dx) ? (md, mg) : (mg, md);
      return VisageDetecte(
          f.boundingBox, g, d, point(f, FaceLandmarkType.bottomMouth),
          nez: point(f, FaceLandmarkType.noseBase),
          boucheGauche: bg,
          boucheDroite: bd);
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
  /// Déformation du visage (la photo elle-même est étirée / gonflée)
  final bool deforme;
  const EffetVisage(this.id, this.nom, this.emoji, {this.deforme = false});

  static bool estDeformation(String id) =>
      tous.any((e) => e.id == id && e.deforme);

  static const tous = [
    EffetVisage('aucun', 'Aucun', '🚫'),
    EffetVisage('lunettes', 'Lunettes', '🕶️'),
    EffetVisage('couronne', 'Couronne', '👑'),
    EffetVisage('coeurs', 'Yeux cœurs', '😍'),
    EffetVisage('fleurs', 'Fleurs', '🌸'),
    EffetVisage('aureole', 'Auréole', '😇'),
    EffetVisage('paillettes', 'Paillettes', '✨'),
    EffetVisage('feu', 'En feu', '🔥'),
    // Déformations (comme TikTok), photos seulement
    EffetVisage('gros_yeux', 'Gros yeux', '👀', deforme: true),
    EffetVisage('grande_bouche', 'Grande bouche', '👄', deforme: true),
    EffetVisage('singe', 'Singe', '🐒', deforme: true),
    EffetVisage('alien', 'Extraterrestre', '👽', deforme: true),
    EffetVisage('grosse_tete', 'Grosse tête', '🎈', deforme: true),
    EffetVisage('etire', 'Visage étiré', '🍐', deforme: true),
    EffetVisage('petit', 'Petit visage', '😜', deforme: true),
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
        return [_emoji('👑', haut + versHaut * largeur * 0.12, largeur * 0.42, angle)];
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
      case 'singe':
        // Oreilles de singe de chaque côté du visage, à hauteur des yeux
        final cote = Offset(math.cos(angle), math.sin(angle));
        final yeux = ecran(v.milieuYeux);
        final r = largeur * 0.2;
        return [
          for (final sens in [-1.0, 1.0])
            Positioned(
              left: (yeux + cote * (sens * largeur * 0.58)).dx - r,
              top: (yeux + cote * (sens * largeur * 0.58)).dy - r,
              width: r * 2,
              height: r * 2,
              child: CustomPaint(painter: _OreilleSinge()),
            ),
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

class _OreilleSinge extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF7A4A24));
    canvas.drawCircle(c, r * 0.62, Paint()..color = const Color(0xFFE9A7A0));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Photo DÉFORMÉE autour des visages (gros yeux, singe, extraterrestre…) :
/// une grille posée sur la photo est gonflée / pincée près des points du
/// visage, puis l'image est redessinée sur cette grille (même principe
/// que les déformations de TikTok, en 2D). Affichée en BoxFit.contain.
class PhotoDeformee extends StatefulWidget {
  final String chemin;
  final ResultatVisages resultat;
  final String effet;
  const PhotoDeformee(
      {super.key,
      required this.chemin,
      required this.resultat,
      required this.effet});

  @override
  State<PhotoDeformee> createState() => _PhotoDeformeeState();
}

class _PhotoDeformeeState extends State<PhotoDeformee> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final octets = await File(widget.chemin).readAsBytes();
      // Réduite à 1600 px de large : assez net, léger en mémoire
      final largeur = widget.resultat.tailleImage.width;
      final codec = await ui.instantiateImageCodec(octets,
          targetWidth: largeur > 1600 ? 1600 : null);
      final image = (await codec.getNextFrame()).image;
      if (mounted) {
        setState(() => _image = image);
      } else {
        image.dispose();
      }
    } catch (e) {
      debugPrint('Photo déformée : $e');
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    if (img == null) {
      return Image.file(File(widget.chemin), fit: BoxFit.contain);
    }
    return CustomPaint(
      size: Size.infinite,
      painter: _PeintreDeformation(img, widget.resultat, widget.effet),
    );
  }
}

/// Une opération de déformation : gonfler (force > 0) ou pincer (< 0) un
/// disque, éventuellement seulement en hauteur ou en largeur.
class _Bulle {
  final Offset centre;
  final double rayon, force;
  final double fx, fy; // part de l'effet en largeur / hauteur
  const _Bulle(this.centre, this.rayon, this.force, {this.fx = 1, this.fy = 1});

  Offset appliquer(Offset p) {
    final d = p - centre;
    final dist = d.distance;
    if (dist >= rayon || rayon <= 0) return p;
    final t = 1 - dist / rayon;
    final k = force * t * t;
    return Offset(p.dx + d.dx * k * fx, p.dy + d.dy * k * fy);
  }
}

class _PeintreDeformation extends CustomPainter {
  final ui.Image image;
  final ResultatVisages resultat;
  final String effet;
  late final ui.Vertices _maillage = _construire();

  _PeintreDeformation(this.image, this.resultat, this.effet);

  /// Les déformations d'un visage (coordonnées de l'image réduite).
  List<_Bulle> _bulles(VisageDetecte v, double k) {
    Offset px(Offset o) => o * k;
    final w = v.cadre.width * k;
    final c = px(v.cadre.center);
    final ecart = v.ecartYeux * k;
    final yeux = [
      if (v.oeilGauche != null) px(v.oeilGauche!),
      if (v.oeilDroit != null) px(v.oeilDroit!),
    ];
    final bouche = px(v.centreBouche);
    final nez = v.nez != null ? px(v.nez!) : (px(v.milieuYeux) + bouche) / 2;
    final front = Offset(c.dx, v.cadre.top * k + w * 0.12);
    final menton = Offset(c.dx, v.cadre.bottom * k);
    switch (effet) {
      case 'gros_yeux':
        return [for (final o in yeux) _Bulle(o, ecart * 0.62, 0.9)];
      case 'grande_bouche':
        return [_Bulle(bouche, w * 0.38, 1.1, fx: 1.25, fy: 0.9)];
      case 'singe':
        return [
          for (final o in yeux) _Bulle(o, ecart * 0.5, 0.55),
          // museau qui avance : nez + bouche gonflés
          _Bulle((nez + bouche) / 2, w * 0.36, 0.95, fx: 1.15),
          _Bulle(front, w * 0.45, -0.3), // front plus bas
        ];
      case 'alien':
        return [
          _Bulle(front, w * 0.7, 0.75, fy: 1.2), // énorme front
          for (final o in yeux) _Bulle(o, ecart * 0.6, 0.7),
          _Bulle(menton, w * 0.45, -0.6), // menton minuscule
          _Bulle(bouche, w * 0.3, -0.35),
        ];
      case 'grosse_tete':
        return [_Bulle(c, w * 0.95, 0.55)];
      case 'etire':
        return [_Bulle(c, w * 1.0, 0.55, fx: -0.35, fy: 1.2)];
      case 'petit':
        return [_Bulle(c, w * 0.9, -0.45)];
    }
    return const [];
  }

  ui.Vertices _construire() {
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    final k = iw / resultat.tailleImage.width; // image réduite / d'origine
    final bulles = [for (final v in resultat.visages) ..._bulles(v, k)];
    const colonnes = 56;
    final lignes = (colonnes * ih / iw).round().clamp(10, 140);
    final positions = <Offset>[];
    final textures = <Offset>[];
    for (var j = 0; j <= lignes; j++) {
      for (var i = 0; i <= colonnes; i++) {
        final t = Offset(iw * i / colonnes, ih * j / lignes);
        var p = t;
        for (final b in bulles) {
          p = b.appliquer(p);
        }
        positions.add(p);
        textures.add(t);
      }
    }
    final indices = <int>[];
    for (var j = 0; j < lignes; j++) {
      for (var i = 0; i < colonnes; i++) {
        final a = j * (colonnes + 1) + i;
        final b = a + 1, c = a + colonnes + 1, d = c + 1;
        indices.addAll([a, b, c, b, d, c]);
      }
    }
    return ui.Vertices(ui.VertexMode.triangles, positions,
        textureCoordinates: textures, indices: indices);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    final k = math.min(size.width / iw, size.height / ih);
    canvas.save();
    canvas.translate((size.width - iw * k) / 2, (size.height - ih * k) / 2);
    canvas.scale(k);
    canvas.clipRect(Rect.fromLTWH(0, 0, iw, ih));
    final pinceau = Paint()
      ..filterQuality = FilterQuality.medium
      ..shader = ImageShader(
          image, TileMode.clamp, TileMode.clamp, Matrix4.identity().storage);
    canvas.drawVertices(_maillage, BlendMode.srcOver, pinceau);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PeintreDeformation old) =>
      old.image != image || old.effet != effet || old.resultat != resultat;
}
