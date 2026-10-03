import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

// ══════════════════════════════════════════════════════════════════
//  LÉGENDE DE STORY (éditeur façon Snap)
//  Même bulle dans l'éditeur et dans les deux viewers, pour que la story
//  s'affiche exactement comme l'auteur l'a placée.
// ══════════════════════════════════════════════════════════════════

/// Bulle de légende, agrandie par [echelle] (1 = taille normale).
class BulleLegende extends StatelessWidget {
  final String texte;
  final double echelle;
  const BulleLegende({super.key, required this.texte, this.echelle = 1});

  @override
  Widget build(BuildContext context) {
    final largeurMax = MediaQuery.of(context).size.width * 0.8;
    return Transform.scale(
      scale: echelle,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: largeurMax),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(texte,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.3)),
        ),
      ),
    );
  }
}

/// Légende posée à l'endroit choisi par l'auteur : ([x], [y]) = centre de
/// la bulle en fraction de l'écran (0–1). À mettre dans un Stack plein écran.
class LegendePlacee extends StatelessWidget {
  final String texte;
  final double x, y, echelle;
  const LegendePlacee({
    super.key,
    required this.texte,
    required this.x,
    required this.y,
    this.echelle = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (_, box) => Stack(children: [
            Positioned(
              left: x.clamp(0.0, 1.0) * box.maxWidth,
              top: y.clamp(0.0, 1.0) * box.maxHeight,
              child: FractionalTranslation(
                translation: const Offset(-0.5, -0.5),
                child: BulleLegende(texte: texte, echelle: echelle),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Vidéo raccourcie : démarre à [debut] et reboucle (ou s'arrête) à [fin].
/// Renvoie l'écouteur ajouté (à retirer si le contrôleur est réutilisé).
VoidCallback? jouerPassage(VideoPlayerController ctrl,
    {Duration? debut, Duration? fin, bool boucle = true}) {
  final d = debut ?? Duration.zero;
  if (d > Duration.zero) ctrl.seekTo(d);
  if (fin == null) return null;
  void ecouteur() {
    if (ctrl.value.position >= fin) {
      if (boucle) {
        ctrl.seekTo(d);
      } else {
        ctrl.pause();
      }
    }
  }

  ctrl.addListener(ecouteur);
  return ecouteur;
}
